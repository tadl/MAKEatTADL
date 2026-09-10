// Run after assets:precompile with Playwright available to Node and Chrome installed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

(async () => {
  const assets = path.resolve(__dirname, '../../public/assets');
  const manifests = fs.readdirSync(assets).filter(name => /^\.sprockets-manifest.*\.json$/.test(name));
  assert.equal(manifests.length, 1, 'Precompile assets before running this check');
  const manifest = JSON.parse(fs.readFileSync(path.join(assets, manifests[0]), 'utf8'));
  const adminAsset = manifest.assets['rails_admin/application.js'];
  assert.ok(adminAsset, 'The compiled RailsAdmin JavaScript must be present');

  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  try {
    const page = await browser.newPage();
    await page.setContent('<!doctype html><html><head></head><body></body></html>');
    await page.addScriptTag({ path: path.join(assets, adminAsset) });
    const result = await page.evaluate(async () => {
      const anchor = jQuery('<div id="anchor" style="position:absolute;left:100px;top:100px;width:50px;height:50px"></div>').appendTo('body');
      const popup = jQuery('<div style="position:absolute;width:20px;height:20px"></div>').appendTo('body');
      popup.position({ of: '#anchor', my: 'left top', at: 'right bottom', collision: 'none' });
      const offset = popup.offset();
      window.positionTestExecuted = false;
      let rejected = false;
      try {
        popup.position({
          of: '<img src="data:image/png,invalid" onerror="window.positionTestExecuted=true">',
          my: 'left top', at: 'right bottom', collision: 'none'
        });
      } catch { rejected = true; }
      await new Promise(resolve => setTimeout(resolve, 100));
      anchor.remove();
      popup.remove();
      return { offset, rejected, executed: window.positionTestExecuted };
    });
    assert.ok(Math.abs(result.offset.left - 150) < 1, 'Normal horizontal positioning must work');
    assert.ok(Math.abs(result.offset.top - 150) < 1, 'Normal vertical positioning must work');
    assert.equal(result.rejected, true, 'HTML must be rejected as an invalid selector');
    assert.equal(result.executed, false, 'The positioning target must not execute HTML');
    console.log('Compiled RailsAdmin positioning: normal selector works; HTML injection rejected.');
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
