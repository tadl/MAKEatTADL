// Requires precompiled assets, the local test database, Playwright, and Chrome.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const { spawnSync } = require('node:child_process');
const { chromium } = require('playwright');

(async () => {
  const root = path.resolve(__dirname, '../..');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'make-stats-browser-'));
  let browser;
  let server;
  try {
    const rendered = spawnSync('rbenv', ['exec', 'bundle', 'exec', 'ruby', 'test/browser/render_stats_pages.rb'], {
      cwd: root, encoding: 'utf8', env: { ...process.env,
        RAILS_ENV: 'test', DATABASE_URL: 'postgresql:///make_at_tadl_test',
        RBENV_VERSION: fs.readFileSync(path.join(root, '.ruby-version'), 'utf8').trim(),
        STATS_BROWSER_PAGES: directory }
    });
    assert.equal(rendered.status, 0, rendered.stdout + rendered.stderr);
    server = http.createServer((req, res) => {
      const url = new URL(req.url, 'http://localhost');
      let file;
      if (url.pathname.startsWith('/assets/')) {
        const assetRoot = path.join(root, 'public/assets');
        file = path.resolve(assetRoot, '.' + url.pathname.slice('/assets'.length));
        if (!file.startsWith(assetRoot + path.sep)) { res.writeHead(404).end(); return; }
      } else if (url.pathname === '/admin/stats') {
        file = path.join(directory, url.search ? 'filtered.html' : 'stats.html');
      } else if (url.pathname === '/admin') {
        file = path.join(directory, 'dashboard.html');
      }
      if (!file || !fs.existsSync(file)) { res.writeHead(404).end(); return; }
      const type = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml' }[path.extname(file)];
      res.setHeader('Content-Type', type ? type + '; charset=utf-8' : 'application/octet-stream');
      fs.createReadStream(file).pipe(res);
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const origin = `http://127.0.0.1:${server.address().port}`;
    browser = await chromium.launch({ channel: 'chrome', headless: true });
    const page = await browser.newPage();
    const errors = [];
    const legacyAssets = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => {
      if (request.url().includes('/rails_admin/')) legacyAssets.push(request.url());
    });
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.route('https://example.com/avatar.png', route => route.fulfill({ status: 204 }));
    // Delay the first Chart.js response beyond turbo:load to expose the cold-navigation race.
    await page.route('https://cdn.jsdelivr.net/npm/chart.js@*/**', async route => {
      await new Promise(resolve => setTimeout(resolve, 750));
      await route.continue();
    });
    await page.goto(origin + '/admin');
    await page.waitForFunction(() => window.Turbo);
    await page.evaluate(() => { window.navigationSentinel = true; });
    await page.locator('a[href="/admin/stats"]').first().click();
    await page.waitForURL('**/admin/stats');
    assert.equal(await page.evaluate(() => window.navigationSentinel), true, 'Use Turbo navigation, not a reload');

    async function assertCharts(expectedDays) {
      await page.waitForFunction(() => {
        const ids = ['printsPerDayChart', 'filamentPerDayChart', 'filamentColorChart'];
        return window.Chart && ids.every(id => Chart.getChart(document.getElementById(id)));
      }, null, { timeout: 10000 });
      const state = await page.evaluate(() => ({
        count: Object.keys(Chart.instances).length,
        days: Chart.getChart(document.getElementById('printsPerDayChart')).data.labels.length
      }));
      assert.equal(state.count, 3, 'Only the current page charts should remain alive');
      if (expectedDays) assert.equal(state.days, expectedDays);
    }
    await assertCharts(30);
    const today = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Detroit' });
    await page.evaluate(url => Turbo.visit(url), origin + `/admin/stats?start=${today}&end=${today}`);
    await page.waitForURL('**/admin/stats?*');
    await assertCharts(1);
    await page.evaluate(url => Turbo.visit(url), origin + '/admin');
    await page.waitForURL('**/admin');
    assert.equal(await page.evaluate(() => Object.keys(Chart.instances).length), 0);
    await page.goBack();
    await page.waitForURL('**/admin/stats?*');
    await assertCharts(1);
    await page.reload();
    await assertCharts(1);

    // The custom workspace keeps its mobile navigation and reports within the viewport.
    await page.setViewportSize({ width: 390, height: 844 });
    const navigationButton = page.getByRole('button', { name: 'Toggle navigation' });
    await navigationButton.click();
    assert.equal(await navigationButton.getAttribute('aria-expanded'), 'true');
    await page.getByRole('navigation', { name: 'Staff navigation' }).getByRole('link', { name: 'Statistics', exact: true }).click();
    await page.waitForURL('**/admin/stats');
    await assertCharts(30);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true,
      'The narrow staff page should not overflow horizontally');
    assert.equal(await page.locator('details summary').filter({ hasText: 'Daily totals' }).count(), 1);

    // Failed optional chart loading leaves readable report data and an explicit fallback.
    const fallbackPage = await browser.newPage();
    const fallbackErrors = [];
    fallbackPage.on('pageerror', error => fallbackErrors.push(error.message));
    await fallbackPage.route('https://cdn.jsdelivr.net/npm/chart.js@*/**', route => route.abort());
    await fallbackPage.goto(origin + '/admin/stats');
    const fallback = fallbackPage.locator('[data-admin-stats-target="error"]');
    await fallback.waitFor({ state: 'visible' });
    assert.equal(await fallbackPage.getByRole('heading', { name: 'Submissions', exact: true }).count(), 1);
    await fallbackPage.locator('details summary').filter({ hasText: 'Daily totals' }).click();
    assert.equal(await fallbackPage.getByRole('columnheader', { name: 'Filament (g)', exact: true }).count(), 1);
    assert.deepEqual(fallbackErrors, []);
    await fallbackPage.close();

    assert.deepEqual(errors, []);
    assert.deepEqual(legacyAssets, [], 'Custom staff pages should not load RailsAdmin assets');
    console.log('Custom stats passed: delayed Turbo visit, filtering, chart cleanup, history, reload, mobile layout, and readable failure fallback.');
  } finally {
    if (browser) await browser.close();
    if (server) await new Promise(resolve => server.close(resolve));
    fs.rmSync(directory, { recursive: true, force: true });
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
