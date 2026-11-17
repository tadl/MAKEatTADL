// Requires compiled assets, a dedicated empty local test database, Playwright, and Chrome.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const { spawnSync } = require('node:child_process');
const { chromium } = require('playwright');

(async () => {
  const root = path.resolve(__dirname, '../..');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'make-admin-layout-'));
  const screenshots = process.env.ADMIN_SCREENSHOTS;
  let browser;
  let server;
  const mutations = [];
  try {
    const rendered = spawnSync('rbenv', ['exec', 'bundle', 'exec', 'ruby', 'test/browser/render_admin_pages.rb'], {
      cwd: root, encoding: 'utf8', env: { ...process.env, RAILS_ENV: 'test',
        DATABASE_URL: 'postgresql:///make_at_tadl_test',
        RBENV_VERSION: fs.readFileSync(path.join(root, '.ruby-version'), 'utf8').trim(),
        ADMIN_BROWSER_PAGES: directory }
    });
    assert.equal(rendered.status, 0, rendered.stdout + rendered.stderr);
    const pages = JSON.parse(fs.readFileSync(path.join(directory, 'pages.json'), 'utf8'));
    const thumbnailEntries = Object.entries(pages).filter(([url]) => /\/thumbnail$/.test(url));
    assert.ok(thumbnailEntries.length >= 2, 'Generated library thumbnail responses are exported.');
    for (const [, filename] of thumbnailEntries) {
      assert.match(fs.readFileSync(path.join(directory, filename), 'utf8'), /<polygon\b/, 'Thumbnails render actual mesh faces.');
    }
    server = http.createServer((req, res) => {
      if (!['GET', 'HEAD'].includes(req.method)) {
        let body = '';
        req.setEncoding('utf8');
        req.on('data', chunk => { body += chunk; });
        req.on('end', () => {
          mutations.push({ url: req.url, method: req.method, body, contentType: req.headers['content-type'] });
          res.writeHead(303, { Location: '/admin' }).end();
        });
        return;
      }
      const url = new URL(req.url, 'http://localhost');
      let file;
      if (url.pathname.startsWith('/assets/')) {
        const assetRoot = path.join(root, 'public/assets');
        file = path.resolve(assetRoot, '.' + url.pathname.slice('/assets'.length));
        if (!file.startsWith(assetRoot + path.sep)) return res.writeHead(404).end();
      } else if (pages[url.pathname]) {
        file = path.join(directory, pages[url.pathname]);
      }
      if (!file || !fs.existsSync(file)) return res.writeHead(404).end();
      const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css',
        '.png': 'image/png', '.svg': 'image/svg+xml', '.stl': 'model/stl' }[path.extname(file)];
      res.setHeader('Content-Type', mime && (mime.startsWith('text/') || mime === 'image/svg+xml') ? `${mime}; charset=utf-8` : mime || 'application/octet-stream');
      fs.createReadStream(file).pipe(res);
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const origin = `http://127.0.0.1:${server.address().port}`;
    browser = await chromium.launch({ channel: 'chrome', headless: true });
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, reducedMotion: 'reduce' });
    const errors = [];
    const nativeDialogs = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('dialog', async dialog => { nativeDialogs.push(dialog.type()); await dialog.dismiss(); });
    const htmlPages = Object.entries(pages).filter(([url, name]) => url.startsWith('/admin') && name.endsWith('.html'));
    const dialog = page.locator('#app-dialog');
    const cancelDialog = dialog.locator('[data-dialog-cancel]');
    const acceptDialog = dialog.locator('[data-dialog-accept]');
    let confirmationCount = 0;
    if (screenshots) fs.mkdirSync(screenshots, { recursive: true });

    async function waitForDialogs() {
      await page.waitForFunction(() => window.Turbo && typeof window.Turbo.config.forms.confirm === 'function' && document.getElementById('app-dialog'));
    }

    async function assertFocused(locator, message) {
      assert.equal(await locator.evaluate(element => element === document.activeElement), true, message);
    }

    async function assertViewportDialog() {
      const dimensions = await dialog.evaluate(element => {
        const bounds = element.getBoundingClientRect();
        return { x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height, viewportWidth: innerWidth, viewportHeight: innerHeight };
      });
      assert.ok(dimensions.x >= 8 && dimensions.y >= 8, 'Dialog stays within the viewport.');
      assert.ok(dimensions.x + dimensions.width <= dimensions.viewportWidth - 8, 'Dialog has no horizontal viewport overflow.');
      assert.ok(dimensions.y + dimensions.height <= dimensions.viewportHeight - 8, 'Dialog has no vertical viewport overflow.');
      assert.ok(Math.abs(dimensions.x + dimensions.width / 2 - dimensions.viewportWidth / 2) <= 2, 'Dialog is centered horizontally.');
      assert.ok(Math.abs(dimensions.y + dimensions.height / 2 - dimensions.viewportHeight / 2) <= 2, 'Dialog is centered vertically.');
    }

    for (const [url, name] of htmlPages) {
      await page.goto(origin + url);
      await page.waitForFunction(() => window.Stimulus && window.Turbo);
      await waitForDialogs();
      assert.equal(await page.locator('main h1').count(), 1, `${name}: one page heading`);
      assert.ok(await page.locator('main h1').textContent(), `${name}: page has a title`);
      assert.equal(await page.locator('link[href*="rails_admin"],script[src*="rails_admin"]').count(), 0);
      assert.equal(await page.locator('link[rel="stylesheet"][href*="bootstrap"]').count(), 0);
      assert.equal(await page.locator('body').evaluate(element => getComputedStyle(element).fontFamily.includes('system-ui')), true);
      for (const requiredSelect of await page.locator('form[data-turbo-confirm] select[required]').all()) {
        if (!await requiredSelect.inputValue()) {
          const value = await requiredSelect.locator('option[value]:not([value=""])').first().getAttribute('value');
          await requiredSelect.selectOption(value);
        }
      }
      const confirmations = page.locator('form[data-turbo-confirm], button[data-turbo-confirm], input[type="submit"][data-turbo-confirm], a[data-turbo-confirm]');
      for (const confirmation of await confirmations.all()) {
        const submitter = await confirmation.evaluate(element => element.tagName === 'FORM')
          ? confirmation.locator('button[type="submit"], input[type="submit"], button:not([type])').first()
          : confirmation;
        // Read-only resource lists have no action to confirm.
        if (await submitter.count() === 0) continue;
        const message = await confirmation.getAttribute('data-turbo-confirm');
        const label = await submitter.evaluate(element => element.textContent.trim() || element.value);
        const danger = await submitter.evaluate(element => element.classList.contains('admin-btn-danger'));
        const before = mutations.length;
        await submitter.click();
        await dialog.waitFor({ state: 'visible' });
        assert.equal(await dialog.locator('#app-dialog-title').textContent(), 'Confirm action');
        assert.equal(await dialog.locator('#app-dialog-message').textContent(), message);
        assert.equal(await acceptDialog.textContent(), label);
        if (danger) assert.equal(await dialog.getAttribute('data-kind'), 'danger');
        await assertFocused(cancelDialog, `${name}: Cancel initially receives focus.`);
        if (screenshots && name === 'job.html') await page.screenshot({ path: path.join(screenshots, 'confirmation-desktop.png') });
        await cancelDialog.click();
        await dialog.waitFor({ state: 'hidden' });
        await assertFocused(submitter, `${name}: cancel returns focus to the triggering control.`);
        assert.equal(mutations.length, before, `${name}: cancelling sends no mutation request.`);
        confirmationCount += 1;
      }
      if (screenshots && ['overview.html', 'jobs.html', 'job.html', 'models.html', 'job-conversation.html'].includes(name)) {
        await page.screenshot({ path: path.join(screenshots, name.replace('.html', '-desktop.png')), fullPage: true });
      }
      await page.setViewportSize({ width: 390, height: 844 });
      const overflow = await page.evaluate(() => ({
        width: document.documentElement.scrollWidth,
        viewport: innerWidth,
        elements: [...document.querySelectorAll('body *')]
          .filter(element => element.getBoundingClientRect().right > innerWidth + 1)
          .slice(0, 20).map(element => ({ tag: element.tagName, class: element.className, width: element.getBoundingClientRect().width, text: element.textContent.slice(0, 80) }))
      }));
      assert.ok(overflow.width <= overflow.viewport, `${name}: no page-wide overflow on mobile: ${JSON.stringify(overflow)}`);
      if (screenshots && ['overview.html', 'jobs.html', 'job-edit.html', 'models.html'].includes(name)) {
        // Reload after the resize assertion so screenshots show a clean mobile
        // compositor rather than a resized desktop sticky-sidebar layer.
        await page.reload();
        await page.waitForFunction(() => window.Stimulus && window.Turbo);
        await page.screenshot({ path: path.join(screenshots, name.replace('.html', '-mobile.png')) });
      }
      await page.setViewportSize({ width: 1440, height: 1000 });
    }

    await page.goto(origin + '/admin');
    await page.waitForFunction(() => window.Stimulus && window.Turbo);
    await page.evaluate(() => { window.navigationSentinel = true; });
    await page.locator('nav a', { hasText: 'Model library' }).click();
    await page.waitForURL('**/admin/models');
    assert.equal(await page.evaluate(() => window.navigationSentinel), true);
    assert.deepEqual(await page.locator('select[name="collection"] option').allTextContents(),
      ['All collections', 'Staff library', 'Assistive', 'Fidget']);
    assert.equal(await page.locator('article .admin-badge', { hasText: /^Patron$/ }).count(), 0);
    const generatedImage = page.getByRole('link', { name: 'View Page-turning aid', exact: true }).locator('img');
    await generatedImage.scrollIntoViewIfNeeded();
    await page.waitForFunction(() => {
      const image = document.querySelector('a[aria-label="View Page-turning aid"] img');
      return image && image.complete && image.naturalWidth > 0;
    });
    assert.match(await generatedImage.getAttribute('src'), /\/admin\/models\/\d+\/thumbnail$/);
    const missingCard = page.locator('article').filter({ has: page.getByRole('link', { name: 'View Missing model file', exact: true }) });
    assert.equal(await missingCard.locator('img').count(), 0);
    assert.equal(await missingCard.getByText('No model file', { exact: true }).count(), 1);
    const photoOnlyCard = page.locator('article').filter({ has: page.getByRole('link', { name: 'View Photo-only model', exact: true }) });
    const uploadedImage = photoOnlyCard.locator('img');
    await uploadedImage.scrollIntoViewIfNeeded();
    await page.waitForFunction(() => {
      const image = document.querySelector('a[aria-label="View Photo-only model"] img');
      return image && image.complete && image.naturalWidth > 0;
    });
    assert.match(await uploadedImage.getAttribute('src'), /\/rails\/active_storage\/blobs\//);
    assert.equal(await photoOnlyCard.getByText('No model file', { exact: true }).count(), 1);
    await page.getByRole('link', { name: 'View Cable organizer', exact: true }).click();
    await page.getByRole('link', { name: 'Print again', exact: true }).waitFor();
    assert.match(await page.getByRole('link', { name: 'Print again', exact: true }).getAttribute('href'), /\/admin\/jobs\/new\?printable_model_id=\d+/);
    const preview = page.locator('details[data-controller="stl-preview"]').first();
    await preview.locator('summary').click();
    await preview.locator('canvas').waitFor({ timeout: 30000 });
    await preview.getByRole('button', { name: 'Zoom in', exact: true }).click();
    await preview.getByRole('button', { name: 'Reset view', exact: true }).click();
    const jobPath = Object.entries(pages).find(([, name]) => name === 'job.html')[0];
    await page.goto(origin + jobPath);
    const saveModel = page.getByRole('link', { name: 'Save to model library', exact: true });
    assert.equal(await saveModel.count(), 1, 'Job overview exposes the model-library action.');
    const saveUrl = new URL(await saveModel.getAttribute('href'), origin);
    assert.match(saveUrl.searchParams.get('source_job_id'), /^\d+$/);
    assert.match(saveUrl.searchParams.get('attachment_id'), /^\d+$/);
    assert.equal(await page.locator('form[action*="/files/"]').count(), 0, 'File deletion stays on the Files screen.');
    await page.locator('nav a', { hasText: 'Jobs', exact: true }).click();
    await page.waitForURL('**/admin/jobs');
    await page.evaluate(() => { window.navigationSentinel = true; });
    const jobRow = page.locator('tr[data-controller="row-link"]').filter({ has: page.locator(`a[href="${jobPath}"]`) });
    const waitForRowController = () => page.waitForFunction(jobPath => {
      const link = document.querySelector(`a[href="${jobPath}"]`);
      return link && window.Stimulus?.getControllerForElementAndIdentifier(link.closest('tr'), 'row-link');
    }, jobPath);
    await waitForRowController();
    const selectionCell = jobRow.locator('[data-row-link-ignore]');
    const checkbox = selectionCell.locator('input[type="checkbox"]');
    await checkbox.check();
    assert.equal(await checkbox.isChecked(), true);
    await selectionCell.click({ position: { x: 2, y: 2 } });
    assert.equal(new URL(page.url()).pathname, '/admin/jobs', 'Checkbox cell padding does not open the job.');
    await checkbox.uncheck();

    const patronCell = jobRow.locator('td').nth(1);
    const patronBounds = await patronCell.boundingBox();
    await page.mouse.move(patronBounds.x + 8, patronBounds.y + 22);
    await page.mouse.down();
    await page.mouse.move(patronBounds.x + patronBounds.width - 8, patronBounds.y + 22, { steps: 12 });
    await page.mouse.up();
    assert.ok(await page.evaluate(() => window.getSelection().toString().length > 0), 'Patron text can be selected.');
    assert.equal(new URL(page.url()).pathname, '/admin/jobs', 'Selecting patron text does not open the job.');
    await page.evaluate(() => window.getSelection().removeAllRanges());

    await patronCell.click({ modifiers: ['Meta'] });
    assert.equal(new URL(page.url()).pathname, '/admin/jobs', 'Modified row clicks do not hijack normal link behavior.');
    await patronCell.click();
    await page.waitForURL(origin + jobPath);
    assert.equal(await page.evaluate(() => window.navigationSentinel), true, 'Row clicks keep Turbo navigation.');

    await page.goto(origin + '/admin/jobs');
    await jobRow.locator('[data-row-link-target="link"]').focus();
    await page.keyboard.press('Enter');
    await page.waitForURL(origin + jobPath);

    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(origin + '/admin/jobs');
    await waitForRowController();
    await patronCell.click();
    await page.waitForURL(origin + jobPath);

    // Test the actual Turbo hook against a harmless synthetic HTTP endpoint.
    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.goto(origin + '/admin');
    await waitForDialogs();
    const pickupButton = page.locator('form[action$="/picked_up"] button').first();
    const pickupAction = await pickupButton.evaluate(element => new URL(element.form.action).pathname);
    const beforeDecisions = mutations.length;
    await pickupButton.click();
    await dialog.waitFor({ state: 'visible' });
    assert.match(await dialog.locator('#app-dialog-message').textContent(), /Price: \$2\.40/,
      'Pickup confirmation includes the stored final price.');
    if (screenshots) await page.screenshot({ path: path.join(screenshots, 'pickup-confirmation-desktop.png') });
    await page.keyboard.press('Shift+Tab');
    await assertFocused(acceptDialog, 'Shift+Tab wraps from Cancel to the final modal control.');
    await page.keyboard.press('Tab');
    await assertFocused(cancelDialog, 'Tab wraps from the final modal control to Cancel.');
    for (let step = 0; step < 4; step++) {
      await page.keyboard.press('Tab');
      assert.equal(await page.evaluate(() => document.activeElement.closest('#app-dialog') !== null), true, 'Tab focus remains inside the modal.');
    }
    await page.keyboard.press('Escape');
    await dialog.waitFor({ state: 'hidden' });
    await assertFocused(pickupButton, 'Escape returns focus to the trigger.');
    assert.equal(mutations.length, beforeDecisions, 'Escape never sends the pending action.');

    await pickupButton.click();
    const pendingMessage = await dialog.locator('#app-dialog-message').textContent();
    const concurrentAnswer = await page.evaluate(() => window.Turbo.config.forms.confirm('Concurrent confirmation must be rejected', document.querySelector('form')));
    assert.equal(concurrentAnswer, false, 'A concurrent confirmation cannot inherit another approval.');
    assert.equal(await dialog.locator('#app-dialog-message').textContent(), pendingMessage);
    await cancelDialog.click();
    assert.equal(mutations.length, beforeDecisions);

    for (const eventName of ['turbo:before-visit', 'turbo:before-render', 'turbo:before-cache']) {
      await pickupButton.click();
      await dialog.waitFor({ state: 'visible' });
      await page.evaluate(name => document.dispatchEvent(new CustomEvent(name)), eventName);
      await dialog.waitFor({ state: 'hidden' });
      assert.equal(await page.evaluate(() => document.documentElement.classList.contains('app-dialog-open')), false);
      assert.equal(mutations.length, beforeDecisions, `${eventName} cancels a pending confirmation.`);
    }

    await page.setViewportSize({ width: 390, height: 844 });
    const literalMessage = 'Delete <img src=x onerror="window.syntheticDialogMarkup = true"> & quoted file? ' + 'long-filename-'.repeat(25);
    await pickupButton.evaluate((element, message) => {
      window.syntheticDialogMarkup = false;
      element.form.dataset.turboConfirm = message;
    }, literalMessage);
    await pickupButton.click();
    await dialog.waitFor({ state: 'visible' });
    assert.equal(await dialog.locator('#app-dialog-message').textContent(), literalMessage);
    assert.equal(await dialog.locator('img, script').count(), 0, 'Confirmation text is not interpreted as markup.');
    assert.equal(await page.evaluate(() => window.syntheticDialogMarkup), false);
    await assertViewportDialog();
    if (screenshots) await page.screenshot({ path: path.join(screenshots, 'confirmation-mobile.png') });
    await cancelDialog.click();
    assert.equal(mutations.length, beforeDecisions);

    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.goto(origin + '/admin');
    await waitForDialogs();
    const originalPage = await page.locator('#main-content').elementHandle();
    await pickupButton.click();
    await dialog.waitFor({ state: 'visible' });
    const [acceptedResponse] = await Promise.all([
      page.waitForResponse(response => response.request().method() === 'POST' && new URL(response.url()).pathname === pickupAction),
      acceptDialog.click()
    ]);
    assert.equal(acceptedResponse.status(), 303);
    await page.waitForURL(origin + '/admin');
    await page.waitForFunction(element => !element.isConnected, originalPage);
    await dialog.waitFor({ state: 'hidden' });
    assert.equal(mutations.length, beforeDecisions + 1, 'A single confirmation sends exactly one mutation.');
    assert.equal(mutations.at(-1).method, 'POST');
    assert.equal(new URL(mutations.at(-1).url, origin).pathname, pickupAction);

    // Exercise the public reCAPTCHA failure handler without contacting Google.
    await page.route('https://www.google.com/recaptcha/**', route => route.fulfill({ status: 200, contentType: 'text/javascript', body: '' }));
    await page.addInitScript(() => {
      window.syntheticCaptchaCalls = 0;
      window.syntheticCaptchaResolvers = [];
      window.syntheticCaptchaToken = 'synthetic-valid-token';
      window.configureSyntheticCaptcha = mode => {
        window.syntheticCaptchaMode = mode;
        if (mode === 'missing') {
          delete window.grecaptcha;
          return;
        }
        window.grecaptcha = { ready: callback => callback(), execute: () => {
          window.syntheticCaptchaCalls += 1;
          // Match the SDK's asynchronous challenge rather than resolving during
          // the original native submit event (which forbids nested requestSubmit).
          if (window.syntheticCaptchaMode === 'success') return new Promise(resolve => setTimeout(() => resolve(window.syntheticCaptchaToken), 0));
          if (window.syntheticCaptchaMode === 'pending') return new Promise(resolve => window.syntheticCaptchaResolvers.push(resolve));
          return Promise.reject(new Error('Synthetic reCAPTCHA failure'));
        } };
      };
      window.configureSyntheticCaptcha(sessionStorage.getItem('synthetic-captcha-mode') || 'reject');
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(origin + '/submit-print');
    await waitForDialogs();
    const beforeAlert = mutations.length;
    await page.locator('form[action="/submit-print"]').evaluate(form => {
      form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
      form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    });
    await dialog.waitFor({ state: 'visible' });
    assert.equal(await dialog.locator('#app-dialog-title').textContent(), 'Unable to verify your request');
    assert.match(await dialog.locator('#app-dialog-message').textContent(), /reCAPTCHA/);
    assert.equal(await cancelDialog.isVisible(), false);
    assert.equal(await acceptDialog.textContent(), 'OK');
    assert.equal(await page.evaluate(() => window.syntheticCaptchaCalls), 1, 'Repeated submit events mint only one CAPTCHA token.');
    await assertFocused(acceptDialog, 'Public alerts initially focus OK.');
    await assertViewportDialog();
    if (screenshots) await page.screenshot({ path: path.join(screenshots, 'alert-mobile.png') });
    await acceptDialog.click();
    await dialog.waitFor({ state: 'hidden' });
    assert.equal(mutations.length, beforeAlert, 'A failed CAPTCHA never submits the request.');
    const publicForm = page.locator('form[action="/submit-print"]');
    const publicSubmit = publicForm.locator('input[type="submit"]');
    assert.equal(await publicSubmit.isEnabled(), true, 'A failed token request re-enables the form.');

    // Playwright 1.61's installed Clock API advances real application deadlines
    // without waiting ten wall-clock seconds for each blocked-provider case.
    await page.clock.install();
    async function openPublicForm(mode) {
      await page.evaluate(value => sessionStorage.setItem('synthetic-captcha-mode', value), mode);
      await page.goto(origin + '/submit-print');
      await waitForDialogs();
      await page.waitForFunction(() => document.querySelector('form[action="/submit-print"]').dataset.recaptchaBound === '1');
      if (mode === 'missing') await page.clock.fastForward(2001);
      await publicForm.locator('#patron_first_name').fill('Avery');
      await publicForm.locator('#patron_last_name').fill('Example');
      await publicForm.locator('#patron_email').fill('avery@example.org');
      await publicForm.locator('#job_url').fill('https://example.org/synthetic-model');
      await publicForm.locator('#job_filament_color').selectOption({ index: 1 });
      assert.equal(await publicForm.evaluate(form => form.checkValidity()), true, 'Synthetic public inputs satisfy native validation.');
      assert.equal(await publicSubmit.isEnabled(), true);
    }

    async function expectPublicPost(token) {
      const before = mutations.length;
      const [response] = await Promise.all([
        page.waitForResponse(item => item.request().method() === 'POST' && new URL(item.url()).pathname === '/submit-print'),
        publicSubmit.click()
      ]);
      assert.equal(response.status(), 303);
      await page.waitForURL(origin + '/admin');
      assert.equal(mutations.length, before + 1, 'A successful token request submits the public form exactly once.');
      const request = mutations.at(-1);
      assert.equal(request.method, 'POST');
      assert.equal(new URL(request.url, origin).pathname, '/submit-print');
      const postedToken = request.contentType?.startsWith('multipart/form-data')
        ? request.body.match(/name="g-recaptcha-response"\r?\n\r?\n([^\r\n]*)/)?.[1]
        : new URLSearchParams(request.body).get('g-recaptcha-response');
      assert.equal(postedToken, token, 'The minted token is preserved in the real HTTP form submission.');
    }

    await openPublicForm('success');
    await expectPublicPost('synthetic-valid-token');

    await openPublicForm('missing');
    const beforeMissing = mutations.length;
    await publicSubmit.click();
    assert.equal(await publicSubmit.isEnabled(), false, 'A pending SDK attempt blocks duplicate submissions.');
    await page.clock.fastForward(10001);
    await dialog.waitFor({ state: 'visible' });
    assert.equal(mutations.length, beforeMissing, 'A missing Google SDK times out without sending a request.');
    assert.equal(await publicSubmit.isEnabled(), true, 'The SDK timeout re-enables submission.');
    await acceptDialog.click();
    await dialog.waitFor({ state: 'hidden' });

    await openPublicForm('pending');
    const beforeLateToken = mutations.length;
    await publicSubmit.click();
    await page.waitForFunction(() => window.syntheticCaptchaResolvers.length === 1);
    await page.clock.fastForward(10001);
    await dialog.waitFor({ state: 'visible' });
    assert.equal(await publicSubmit.isEnabled(), true, 'A token timeout re-enables submission.');
    await page.evaluate(() => window.syntheticCaptchaResolvers.shift()('synthetic-too-late-token'));
    assert.equal(mutations.length, beforeLateToken, 'A token arriving after the deadline cannot submit.');
    assert.equal(await publicForm.locator('[name="g-recaptcha-response"]').inputValue(), '');
    await acceptDialog.click();
    await dialog.waitFor({ state: 'hidden' });
    await page.evaluate(() => {
      window.syntheticCaptchaToken = 'synthetic-retry-token';
      window.configureSyntheticCaptcha('success');
    });
    await expectPublicPost('synthetic-retry-token');

    await openPublicForm('pending');
    const beforeValidation = mutations.length;
    await publicSubmit.click();
    await page.waitForFunction(() => window.syntheticCaptchaResolvers.length === 1);
    await publicForm.locator('#patron_first_name').fill('');
    await page.evaluate(() => window.syntheticCaptchaResolvers.shift()('synthetic-interrupted-token'));
    await page.waitForFunction(() => {
      const form = document.querySelector('form[action="/submit-print"]');
      return !form.dataset.recaptchaDone && !form.querySelector('[name="g-recaptcha-response"]').value && !form.querySelector('input[type="submit"]').disabled;
    });
    assert.equal(mutations.length, beforeValidation, 'Native validation can stop a minted-token submission.');
    await publicForm.locator('#patron_first_name').fill('Avery');
    await page.evaluate(() => {
      window.syntheticCaptchaToken = 'synthetic-validation-retry-token';
      window.configureSyntheticCaptcha('success');
    });
    await expectPublicPost('synthetic-validation-retry-token');
    assert.deepEqual(nativeDialogs, [], 'No browser-native confirm or alert dialogs are used.');
    assert.deepEqual(errors, []);
    assert.ok(confirmationCount >= 12, 'Every exported administrative confirmation surface is exercised.');
    console.log(`Staff layouts passed: ${htmlPages.length} desktop/mobile pages, ${confirmationCount} branded confirmations, CAPTCHA token submission/failure/timeouts/late-token and validation retries, clickable rows, thumbnails, Turbo navigation, and live STL controls.`);
  } finally {
    if (browser) await browser.close();
    if (server) await new Promise(resolve => server.close(resolve));
    fs.rmSync(directory, { recursive: true, force: true });
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
