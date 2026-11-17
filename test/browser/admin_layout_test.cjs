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
      res.setHeader('Content-Type', mime || 'application/octet-stream');
      fs.createReadStream(file).pipe(res);
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const origin = `http://127.0.0.1:${server.address().port}`;
    browser = await chromium.launch({ channel: 'chrome', headless: true });
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, reducedMotion: 'reduce' });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const htmlPages = Object.entries(pages).filter(([, name]) => name.endsWith('.html'));
    if (screenshots) fs.mkdirSync(screenshots, { recursive: true });

    for (const [url, name] of htmlPages) {
      await page.goto(origin + url);
      await page.waitForFunction(() => window.Stimulus && window.Turbo);
      assert.equal(await page.locator('main h1').count(), 1, `${name}: one page heading`);
      assert.ok(await page.locator('main h1').textContent(), `${name}: page has a title`);
      assert.equal(await page.locator('link[href*="rails_admin"],script[src*="rails_admin"]').count(), 0);
      assert.equal(await page.locator('link[rel="stylesheet"][href*="bootstrap"]').count(), 0);
      assert.equal(await page.locator('body').evaluate(element => getComputedStyle(element).fontFamily.includes('system-ui')), true);
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
    assert.deepEqual(errors, []);
    console.log(`Staff layouts passed: ${htmlPages.length} desktop/mobile pages, clickable job rows and independent checkboxes/text selection, collection choices, actual thumbnails, library-save discovery, Turbo navigation, reprint link, and live STL controls.`);
  } finally {
    if (browser) await browser.close();
    if (server) await new Promise(resolve => server.close(resolve));
    fs.rmSync(directory, { recursive: true, force: true });
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
