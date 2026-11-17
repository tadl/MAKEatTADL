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
    await page.getByRole('link', { name: 'View Cable organizer', exact: true }).click();
    await page.getByRole('link', { name: 'Print again', exact: true }).waitFor();
    assert.match(await page.getByRole('link', { name: 'Print again', exact: true }).getAttribute('href'), /\/admin\/jobs\/new\?printable_model_id=\d+/);
    const preview = page.locator('details[data-controller="stl-preview"]').first();
    await preview.locator('summary').click();
    await preview.locator('canvas').waitFor({ timeout: 30000 });
    await preview.getByRole('button', { name: 'Zoom in', exact: true }).click();
    await preview.getByRole('button', { name: 'Reset view', exact: true }).click();
    await page.locator('nav a', { hasText: 'Jobs', exact: true }).click();
    await page.waitForURL('**/admin/jobs');
    assert.deepEqual(errors, []);
    console.log(`Staff layouts passed: ${htmlPages.length} desktop/mobile pages, Turbo library navigation, reprint link, and live STL preview controls.`);
  } finally {
    if (browser) await browser.close();
    if (server) await new Promise(resolve => server.close(resolve));
    fs.rmSync(directory, { recursive: true, force: true });
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
