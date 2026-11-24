// Takes the Grafana screenshots used on the "what Grafana looks like" slides.
// Run by scripts/grafana-shots.sh inside a browser pod on the hub.
//
// The query is deliberately a dull one (one healthy service, info lines, the
// last fifteen minutes): these slides come before round one and must not show
// any of the incidents.
const { chromium } = require('playwright')
const fs = require('fs')

const base = process.env.GRAFANA + '/explore?schemaVersion=1&orgId=1&panes='
const url = (expr, from) => base + encodeURIComponent(JSON.stringify({
  a: {
    datasource: 'workshop-loki',
    queries: [{ refId: 'A', datasource: { type: 'loki', uid: 'workshop-loki' }, expr }],
    range: { from, to: 'now' },
  },
}))
const rect = async (p, sel) => {
  const l = p.locator(sel).first()
  try { await l.waitFor({ timeout: 5000 }); return await l.boundingBox() } catch (e) { return null }
}

;(async () => {
  const b = await chromium.launch()
  // Grafana refuses to start without a locale it recognises.
  const ctx = await b.newContext({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 2, locale: 'en-GB', timezoneId: 'Europe/London' })
  const p = await ctx.newPage()
  await p.goto(url('{service="web", level="info"}', 'now-15m'), { waitUntil: 'networkidle' })
  await p.waitForTimeout(6000)
  const out = {}
  await p.screenshot({ path: 'grafana-explore.png' })
  out.query = await rect(p, '.monaco-editor')
  out.run = await rect(p, '[data-testid="data-testid RefreshPicker run button"]')
  out.timeButton = await rect(p, '[data-testid="data-testid TimePicker Open Button"]')
  await p.locator('[data-testid="data-testid TimePicker Open Button"]').first().click()
  await p.waitForTimeout(1500)
  out.timePanel = await rect(p, '#TimePickerContent')
  await p.screenshot({ path: 'grafana-time.png' })
  // Where things are, in 1280x720 units: the highlights in GrafanaSlides.jsx.
  console.log(JSON.stringify(out, null, 1))
  await b.close()
})()
