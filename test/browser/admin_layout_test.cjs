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
  let persistedPreferences = { theme: 'system', ui_density: 'normal' };
  let failPreferenceSave = false;
  try {
    const rendered = spawnSync('rbenv', ['exec', 'bundle', 'exec', 'ruby', 'test/browser/render_admin_pages.rb'], {
      cwd: root, encoding: 'utf8', env: { ...process.env, RAILS_ENV: 'test',
        DATABASE_URL: 'postgresql:///make_at_tadl_test',
        RBENV_VERSION: fs.readFileSync(path.join(root, '.ruby-version'), 'utf8').trim(),
        ADMIN_BROWSER_PAGES: directory }
    });
    assert.equal(rendered.status, 0, rendered.stdout + rendered.stderr);
    const pages = JSON.parse(fs.readFileSync(path.join(directory, 'pages.json'), 'utf8'));
    const fixtureKey = value => {
      const url = new URL(value, 'http://example.test');
      if (url.searchParams.get('page') === '1') url.searchParams.delete('page');
      if (url.searchParams.get('per_page') === '25') url.searchParams.delete('per_page');
      url.searchParams.sort();
      return url.pathname + url.search;
    };
    const pageFiles = new Map(Object.entries(pages).map(([url, filename]) => [fixtureKey(url), filename]));
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
          const mutation = { url: req.url, method: req.method, body, contentType: req.headers['content-type'] };
          mutations.push(mutation);
          if (new URL(req.url, 'http://example.test').pathname === '/admin/preferences') {
            let preferences;
            if (req.headers['content-type']?.startsWith('application/json')) {
              preferences = JSON.parse(body).preferences || {};
            } else if (req.headers['content-type']?.startsWith('multipart/form-data')) {
              preferences = Object.fromEntries(['theme', 'ui_density'].map(field => {
                const match = body.match(new RegExp(`name="preferences\\[${field}\\]"\\r?\\n\\r?\\n([^\\r\\n]*)`));
                return [field, match?.[1]];
              }).filter(([, value]) => value !== undefined));
            } else {
              const values = new URLSearchParams(body);
              preferences = Object.fromEntries(['theme', 'ui_density'].map(field => [field, values.get(`preferences[${field}]`)]).filter(([, value]) => value !== null));
            }
            mutation.preferences = preferences;
            const next = { ...persistedPreferences, ...preferences };
            const valid = Object.keys(preferences).every(field => ['theme', 'ui_density'].includes(field)) &&
              ['system', 'light', 'dark'].includes(next.theme) && ['normal', 'condensed'].includes(next.ui_density);
            if (failPreferenceSave || !valid) {
              res.writeHead(422, { 'Content-Type': 'application/json; charset=utf-8' }).end(JSON.stringify({ error: 'Synthetic preference save failed.' }));
            } else {
              persistedPreferences = next;
              res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' }).end(JSON.stringify(persistedPreferences));
            }
            return;
          }
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
      } else if (pageFiles.has(fixtureKey(url.href))) {
        file = path.join(directory, pageFiles.get(fixtureKey(url.href)));
      }
      if (fixtureKey(url.href) === '/admin/jobs' && persistedPreferences.theme === 'dark' && persistedPreferences.ui_density === 'condensed') {
        file = path.join(directory, 'jobs-dark-condensed.html');
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
    let avatarFails = false;
    await page.route('https://example.org/synthetic-avatar.png', route => route.fulfill(avatarFails
      ? { status: 404, body: '' }
      : { status: 200, contentType: 'image/png', body: fs.readFileSync(path.join(directory, 'synthetic-avatar.png')) }));
    await page.emulateMedia({ colorScheme: 'light' });
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

    async function waitForControllers(identifier) {
      await page.waitForFunction(name => [...document.querySelectorAll(`[data-controller~="${name}"]`)]
        .every(element => window.Stimulus?.getControllerForElementAndIdentifier(element, name)), identifier);
    }

    const paginatedFiles = new Set(['jobs.html', 'jobs-page-2.html', 'jobs-middle-page.html', 'jobs-last-page.html',
      'jobs-50.html', 'jobs-100.html', 'patron.html', 'activity.html']);
    const smallListFiles = new Set(['patrons.html', 'models.html', 'printers.html', 'locations.html']);

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
      assert.equal(await page.locator('html').getAttribute('data-theme'), 'system');
      assert.equal(await page.locator('html').getAttribute('data-density'), 'normal');
      assert.equal(await page.locator('details.admin-user-menu').count(), 1);
      if (smallListFiles.has(name)) {
        assert.equal(await page.getByRole('navigation', { name: /^Pagination (top|bottom)$/ }).count(), 0, `${name}: small lists have no pagination UI.`);
        assert.equal(await page.locator('select[name="per_page"]').count(), 0, `${name}: small lists have no page-size selector.`);
      }
      if (paginatedFiles.has(name)) {
        const perPage = new URL(url, origin).searchParams.get('per_page') || '25';
        const selectIds = [];
        for (const position of ['top', 'bottom']) {
          const pagination = page.getByRole('navigation', { name: `Pagination ${position}`, exact: true });
          assert.equal(await pagination.count(), 1, `${name}: ${position} pagination is present.`);
          const pageSize = pagination.locator('select[name="per_page"]');
          assert.deepEqual(await pageSize.locator('option').evaluateAll(options => options.map(option => option.value)), ['25', '50', '100']);
          assert.equal(await pageSize.inputValue(), perPage);
          selectIds.push(await pageSize.getAttribute('id'));
          const currentPage = pagination.locator('[aria-current="page"]');
          assert.equal(await currentPage.count(), 1);
          assert.equal(await currentPage.getAttribute('aria-disabled'), 'true');
          assert.equal(await currentPage.evaluate(element => element.tagName), 'SPAN');
          if (name === 'jobs-middle-page.html') assert.match(await pagination.textContent(), /…/);
        }
        assert.ok(selectIds.every(Boolean) && selectIds[0] !== selectIds[1], `${name}: page-size labels have distinct controls.`);
      }
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
        let selectedBulkItem;
        if (!await submitter.isVisible()) {
          await waitForControllers('bulk-selection');
          selectedBulkItem = page.locator('input[data-bulk-selection-target~="item"]').first();
          assert.ok(await selectedBulkItem.count(), `${name}: a hidden bulk action has selectable records.`);
          await selectedBulkItem.check();
          await submitter.waitFor({ state: 'visible' });
        }
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
        if (selectedBulkItem) {
          assert.equal(await selectedBulkItem.isChecked(), true, `${name}: cancelling preserves the selection.`);
          await selectedBulkItem.uncheck();
          await submitter.waitFor({ state: 'hidden' });
        }
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

    // Preference requests use the actual controller contract, while these
    // static fixtures stand in for Rails' separately tested database writes.
    await page.goto(origin + '/admin/jobs');
    await waitForControllers('user-menu');
    const userMenu = page.locator('details.admin-user-menu');
    const userTrigger = userMenu.locator('summary.admin-user-menu-trigger');
    const userPanel = page.locator('#user-menu-panel');
    const themeRadios = userPanel.locator('input[name="preferences[theme]"]');
    const densityRadios = userPanel.locator('input[name="preferences[ui_density]"]');
    const checkedPreference = name => userPanel.locator(`input[name="preferences[${name}]"]:checked`).inputValue();
    const preferenceStatus = userPanel.locator('[data-user-menu-target="status"]');
    const cardStyle = () => page.locator('.admin-card').first().evaluate(element => {
      const style = getComputedStyle(element);
      return { background: style.backgroundColor, color: style.color };
    });

    async function waitForCardStyle(expected) {
      await page.waitForFunction(palette => {
        const style = getComputedStyle(document.querySelector('.admin-card'));
        return style.backgroundColor === palette.background && style.color === palette.color;
      }, expected);
      return cardStyle();
    }

    async function openUserMenu() {
      if (!await userMenu.evaluate(element => element.open)) await userTrigger.click();
      await userPanel.waitFor({ state: 'visible' });
      await page.waitForFunction(() => document.querySelector('.admin-user-menu-trigger').getAttribute('aria-expanded') === 'true');
    }

    async function changePreference(action, success = true) {
      await openUserMenu();
      const [response] = await Promise.all([
        page.waitForResponse(item => item.request().method() === 'PATCH' && new URL(item.url()).pathname === '/admin/preferences'),
        action()
      ]);
      assert.equal(response.status(), success ? 200 : 422);
      await page.waitForFunction(expected => {
        const status = document.querySelector('[data-user-menu-target="status"]')?.textContent;
        const fields = [...document.querySelectorAll('#user-menu-panel input[type="radio"]')];
        return fields.every(field => !field.disabled) && (expected ? status === 'Saved' : status?.includes('Couldn’t save'));
      }, success);
      // Color-scheme invalidation can settle after the fetch callback; observe
      // the rendered frame before measuring inherited light-dark() colors.
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const mutation = mutations.at(-1);
      assert.equal(mutation.method, 'PATCH');
      assert.ok(Object.keys(mutation.preferences).every(field => ['theme', 'ui_density'].includes(field)));
      assert.doesNotMatch(mutation.body, /staff_user_id|user_id|preferences\[id\]/, 'Appearance requests do not select another account.');
    }

    async function savePreference(name, value, success = true) {
      const input = page.locator(`input[name="preferences[${name}]"][value="${value}"]`);
      const label = userPanel.locator('label.admin-segment-option').filter({ has: input });
      await changePreference(() => label.click(), success);
    }

    assert.equal(await userTrigger.getAttribute('aria-controls'), 'user-menu-panel');
    assert.match(await userTrigger.textContent(), /Morgan Example/);
    assert.deepEqual(await themeRadios.evaluateAll(elements => elements.map(element => [element.type, element.value])),
      [['radio', 'system'], ['radio', 'dark'], ['radio', 'light']]);
    assert.deepEqual(await densityRadios.evaluateAll(elements => elements.map(element => [element.type, element.value])),
      [['radio', 'normal'], ['radio', 'condensed']]);
    assert.equal(await userPanel.locator('.admin-segment-button svg').count(), 5, 'Every preference segment has an icon.');
    // The reduced-motion stylesheet intentionally applies a tiny nonzero
    // duration globally; check the normal user experience before restoring it.
    await page.emulateMedia({ colorScheme: 'light', reducedMotion: 'no-preference' });
    await page.waitForFunction(() => [...document.querySelectorAll('.admin-btn, .admin-nav-link, .admin-segment-button')]
      .every(element => getComputedStyle(element).transitionDuration.split(',').every(duration => parseFloat(duration) === 0)));
    assert.equal(await page.locator('.admin-btn, .admin-nav-link, .admin-segment-button').evaluateAll(elements =>
      elements.every(element => getComputedStyle(element).transitionDuration.split(',').every(duration => parseFloat(duration) === 0))),
    true, 'Staff controls switch palettes without color transitions.');
    await page.emulateMedia({ colorScheme: 'light', reducedMotion: 'reduce' });
    await page.waitForFunction(() => {
      const image = document.querySelector('.admin-user-menu-trigger img');
      return image?.complete && image.naturalWidth > 0;
    });
    await userTrigger.focus();
    await page.keyboard.press('Enter');
    await userPanel.waitFor({ state: 'visible' });
    assert.equal(await userPanel.getByRole('group', { name: 'Theme', exact: true }).count(), 1);
    assert.equal(await userPanel.getByRole('group', { name: 'UI density', exact: true }).count(), 1);
    assert.equal(await userPanel.getByRole('link', { name: 'Overview', exact: true }).count(), 1);
    const emptyStatusHeight = await preferenceStatus.evaluate(element => element.getBoundingClientRect().height);
    assert.ok(emptyStatusHeight >= 24, 'The save-status line reserves space before a preference changes.');
    if (screenshots) await page.screenshot({ path: path.join(screenshots, 'user-menu-light-desktop.png') });
    await page.keyboard.press('Tab');
    assert.equal(await page.evaluate(() => document.activeElement.closest('#user-menu-panel') !== null), true);
    await page.keyboard.press('Escape');
    await userPanel.waitFor({ state: 'hidden' });
    await assertFocused(userTrigger, 'Escape returns focus to the user-menu trigger.');
    await openUserMenu();
    await page.getByRole('heading', { name: 'Jobs', exact: true }).click();
    await userPanel.waitFor({ state: 'hidden' });
    assert.equal(await userTrigger.getAttribute('aria-expanded'), 'false');

    await openUserMenu();
    await userPanel.locator('input[name="preferences[theme]"][value="system"]').focus();
    let releasePreferenceRequest;
    const preferenceRequestReleased = new Promise(resolve => { releasePreferenceRequest = resolve; });
    await page.route('**/admin/preferences', async route => {
      await preferenceRequestReleased;
      await route.continue();
    }, { times: 1 });
    const keyboardSave = changePreference(() => page.keyboard.press('ArrowRight'));
    let savingAppearance;
    try {
      await page.waitForFunction(() => {
        const radios = [...document.querySelectorAll('#user-menu-panel input[type="radio"]')];
        return radios.length === 5 && radios.every(input => input.disabled) &&
          document.querySelector('[data-user-menu-target="status"]').textContent === 'Saving…';
      });
      savingAppearance = await userPanel.evaluate(panel => ({
        opacity: [...panel.querySelectorAll('.admin-segment-button')].map(element => getComputedStyle(element).opacity),
        statusHeight: panel.querySelector('[data-user-menu-target="status"]').getBoundingClientRect().height
      }));
    } finally {
      releasePreferenceRequest();
    }
    await keyboardSave;
    assert.deepEqual(savingAppearance.opacity, ['1', '1', '1', '1', '1'], 'Saving does not dim the selected segments.');
    assert.equal(savingAppearance.statusHeight, emptyStatusHeight, 'The Saving status keeps the menu controls in place.');
    assert.equal(await checkedPreference('theme'), 'dark', 'Native arrow keys select and save the next theme segment.');
    assert.equal(await page.evaluate(() => document.activeElement.value), 'dark');
    assert.equal(await preferenceStatus.evaluate(element => element.getBoundingClientRect().height), emptyStatusHeight,
      'A successful save does not move the menu controls.');
    await savePreference('theme', 'light');
    const lightStyle = await cardStyle();
    await savePreference('theme', 'dark');
    const darkStyle = await cardStyle();
    assert.notDeepEqual(darkStyle, lightStyle, `Dark mode changes rendered surfaces and text: ${JSON.stringify({ lightStyle, darkStyle })}`);
    await savePreference('theme', 'system');
    await page.emulateMedia({ colorScheme: 'dark' });
    assert.equal(await page.locator('html').getAttribute('data-theme'), 'system');
    assert.deepEqual(await waitForCardStyle(darkStyle), darkStyle, 'System mode follows a dark OS preference.');
    await page.emulateMedia({ colorScheme: 'light' });
    assert.deepEqual(await waitForCardStyle(lightStyle), lightStyle, 'System mode follows a light OS preference.');
    await savePreference('theme', 'dark');
    const normalRowHeight = await page.locator('.admin-table tbody tr').first().evaluate(element => element.getBoundingClientRect().height);
    await savePreference('ui_density', 'condensed');
    const condensedRowHeight = await page.locator('.admin-table tbody tr').first().evaluate(element => element.getBoundingClientRect().height);
    assert.ok(condensedRowHeight < normalRowHeight - 1, 'Condensed mode measurably reduces table-row height.');
    await page.reload();
    await waitForControllers('user-menu');
    assert.equal(await page.locator('html').getAttribute('data-theme'), 'dark');
    assert.equal(await page.locator('html').getAttribute('data-density'), 'condensed');
    assert.equal(await checkedPreference('theme'), 'dark');
    assert.equal(await checkedPreference('ui_density'), 'condensed');

    failPreferenceSave = true;
    await savePreference('theme', 'light', false);
    assert.equal(await page.locator('html').getAttribute('data-theme'), 'dark', 'A failed save restores the last confirmed theme.');
    assert.equal(await checkedPreference('theme'), 'dark');
    assert.deepEqual(persistedPreferences, { theme: 'dark', ui_density: 'condensed' });
    assert.match(await preferenceStatus.textContent(), /Couldn’t save/);
    failPreferenceSave = false;
    await page.setViewportSize({ width: 390, height: 844 });
    await openUserMenu();
    const menuBounds = await userPanel.boundingBox();
    assert.ok(menuBounds.x >= 0 && menuBounds.x + menuBounds.width <= 390, 'The user menu stays within a narrow viewport.');
    if (screenshots) await page.screenshot({ path: path.join(screenshots, 'user-menu-dark-condensed-mobile.png') });
    await savePreference('ui_density', 'normal');
    await savePreference('theme', 'system');
    await page.keyboard.press('Escape');
    await page.setViewportSize({ width: 1440, height: 1000 });

    await page.goto(origin + '/__fixtures__/staff-jobs');
    await waitForControllers('user-menu');
    await openUserMenu();
    assert.match(await userTrigger.innerText(), /Taylor Example/);
    assert.match(await userTrigger.innerText(), /\bTE\b/, 'Missing avatars use the staff member’s initials.');
    assert.equal(await userTrigger.locator('img').count(), 0);
    assert.equal(await userPanel.getByRole('link', { name: 'Overview', exact: true }).count(), 0);
    assert.equal(await themeRadios.count(), 3, 'Ordinary staff can change their own appearance.');
    assert.equal(await densityRadios.count(), 2);
    const [logoutResponse] = await Promise.all([
      page.waitForResponse(response => new URL(response.url()).pathname === '/logout'),
      userPanel.getByRole('button', { name: 'Log out', exact: true }).click()
    ]);
    assert.equal(logoutResponse.status(), 303);
    const logout = mutations.at(-1);
    const logoutMethod = logout.method === 'POST' ? new URLSearchParams(logout.body).get('_method')?.toUpperCase() || 'POST' : logout.method;
    assert.equal(logoutMethod, 'DELETE', 'Logout retains the Rails DELETE method.');
    await page.waitForURL(origin + '/admin');
    avatarFails = true;
    await page.goto(origin + '/admin/jobs');
    await waitForControllers('user-menu');
    await page.waitForFunction(() => document.querySelector('.admin-user-menu-trigger img')?.hidden === true);
    assert.match(await userTrigger.innerText(), /\bME\b/, 'A failed avatar request falls back to initials.');
    avatarFails = false;

    // Selection is local to the rendered page and participates in the real bulk
    // form, including job checkboxes associated through their form attribute.
    await page.goto(origin + '/admin/jobs');
    await waitForControllers('bulk-selection');
    await waitForControllers('auto-submit');
    const bulk = page.locator('[data-controller~="bulk-selection"]').first();
    const items = bulk.locator('input[data-bulk-selection-target~="item"]');
    const selectAll = bulk.locator('input[data-bulk-selection-target~="all"]').first();
    const bulkActions = bulk.locator('[data-bulk-selection-target~="actions"]').first();
    const topPager = page.getByRole('navigation', { name: 'Pagination top', exact: true });
    const bottomPager = page.getByRole('navigation', { name: 'Pagination bottom', exact: true });
    assert.equal(await items.count(), 25);
    assert.equal(await bulkActions.isVisible(), false, 'Bulk actions start hidden.');
    assert.equal(await topPager.locator('a[rel="prev"]').count(), 0);
    assert.equal(await topPager.locator('[aria-disabled="true"]').filter({ hasText: /Prev/ }).count(), 1);

    await items.first().check();
    assert.equal(await bulkActions.isVisible(), true, 'Selecting one row reveals bulk actions.');
    assert.equal(await selectAll.evaluate(element => element.indeterminate), true);
    const firstId = await items.first().inputValue();
    assert.deepEqual(await items.first().evaluate(element => new FormData(element.form).getAll('ids[]')), [firstId]);

    await selectAll.check();
    assert.equal(await items.evaluateAll(elements => elements.every(element => element.checked)), true);
    assert.equal(await selectAll.evaluate(element => element.indeterminate), false);
    assert.equal(await items.first().evaluate(element => new FormData(element.form).getAll('ids[]').length), 25, 'Select all submits only the visible page.');
    await items.nth(1).uncheck();
    assert.equal(await selectAll.isChecked(), false);
    assert.equal(await selectAll.evaluate(element => element.indeterminate), true);
    await selectAll.check();
    await selectAll.uncheck();
    assert.equal(await items.evaluateAll(elements => elements.every(element => !element.checked)), true);
    assert.equal(await bulkActions.isVisible(), false, 'Clearing the last selection hides bulk actions.');

    await items.first().check();
    await page.evaluate(() => { window.paginationSentinel = true; });
    await topPager.locator('a[rel="next"]').click();
    await page.waitForURL(url => url.pathname === '/admin/jobs' && url.searchParams.get('page') === '2');
    await page.waitForFunction(() => document.querySelector('nav[aria-label="Pagination top"] [aria-current="page"]').textContent.trim() === '2');
    await waitForControllers('bulk-selection');
    assert.equal(await page.evaluate(() => window.paginationSentinel), true, 'Pagination uses Turbo navigation.');
    assert.equal(await items.count(), 25);
    assert.equal(await items.evaluateAll(elements => elements.every(element => !element.checked)), true, 'Navigating to another page resets its selection.');
    assert.equal(await bulkActions.isVisible(), false);

    const lastPagePath = Object.entries(pages).find(([, name]) => name === 'jobs-last-page.html')[0];
    const lastPageNumber = new URL(lastPagePath, origin).searchParams.get('page');
    await topPager.getByRole('link', { name: `Page ${lastPageNumber}`, exact: true }).click();
    await page.waitForURL(url => url.searchParams.get('page') === lastPageNumber);
    await page.waitForFunction(expected => document.querySelector('nav[aria-label="Pagination top"] [aria-current="page"]').textContent.trim() === expected, lastPageNumber);
    for (const pagination of [topPager, bottomPager]) {
      assert.equal(await pagination.locator('a[rel="next"]').count(), 0);
      assert.equal(await pagination.locator('[aria-disabled="true"]').filter({ hasText: /Next/ }).count(), 1);
    }

    await waitForControllers('auto-submit');
    await topPager.locator('select[name="per_page"]').selectOption('50');
    await page.waitForURL(url => url.pathname === '/admin/jobs' && url.searchParams.get('per_page') === '50');
    await page.waitForFunction(() => document.querySelectorAll('input[data-bulk-selection-target~="item"]').length === 50);
    assert.equal(new URL(page.url()).searchParams.get('page') || '1', '1', 'Changing page size resets to the first page.');
    assert.equal(await bottomPager.locator('select[name="per_page"]').inputValue(), '50');
    await waitForControllers('bulk-selection');
    await items.first().check();
    await waitForControllers('auto-submit');
    await bottomPager.locator('select[name="per_page"]').selectOption('100');
    await page.waitForURL(url => url.pathname === '/admin/jobs' && url.searchParams.get('per_page') === '100');
    await page.waitForFunction(() => document.querySelectorAll('input[data-bulk-selection-target~="item"]').length === 100);
    await waitForControllers('bulk-selection');
    assert.equal(await topPager.locator('select[name="per_page"]').inputValue(), '100');
    assert.equal(await items.evaluateAll(elements => elements.every(element => !element.checked)), true);
    assert.equal(await bulkActions.isVisible(), false);
    assert.equal(await page.evaluate(() => window.paginationSentinel), true, 'Page-size changes also preserve Turbo navigation.');

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
    assert.ok(confirmationCount >= 14, 'Every exported administrative confirmation surface is exercised.');
    console.log(`Staff layouts passed: ${htmlPages.length} desktop/mobile pages, user-menu/appearance/avatars, pagination/page sizes/bulk selection, ${confirmationCount} branded confirmations, CAPTCHA token submission/failure/timeouts/late-token and validation retries, clickable rows, thumbnails, Turbo navigation, and live STL controls.`);
  } finally {
    if (browser) await browser.close();
    if (server) await new Promise(resolve => server.close(resolve));
    fs.rmSync(directory, { recursive: true, force: true });
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
