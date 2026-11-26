import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import QRCode from 'qrcode'
import { existsSync, readFileSync } from 'node:fs'

// Where players join. In order: CTF_URL in the environment, then the address
// hub-09 wrote to .state, then a placeholder so the deck still builds before
// there is a hub. The placeholder is obvious on screen on purpose.
function joinAddress() {
  if (process.env.CTF_URL) return process.env.CTF_URL.trim()
  const state = new URL('../.state/ctf-endpoint', import.meta.url)
  if (existsSync(state)) {
    const v = readFileSync(state, 'utf8').trim()
    if (v) return v
  }
  return 'https://ctf.example.com'
}

// Build-time QR codes: the SVG is generated here and bundled as a string, so
// the deck makes no network calls at runtime.
function qrPlugin() {
  const id = 'virtual:qr'
  const resolved = '\0' + id
  const opts = { type: 'svg', margin: 1, errorCorrectionLevel: 'M', color: { dark: '#000000ff', light: '#ffffffff' } }
  return {
    name: 'ctf-qr',
    resolveId(source) {
      if (source === id) return resolved
    },
    async load(source) {
      if (source !== resolved) return
      const repo = 'https://github.com/DMajrekar/kagent-civo-workshop'
      const join = joinAddress()
      if (join.includes('example.com')) {
        this.warn('no CTF address found (CTF_URL or ../.state/ctf-endpoint): the join QR code is a placeholder')
      }
      return [
        `export const repoUrl = ${JSON.stringify(repo)};`,
        `export const repoQr = ${JSON.stringify(await QRCode.toString(repo, opts))};`,
        `export const joinUrl = ${JSON.stringify(join)};`,
        `export const joinQr = ${JSON.stringify(await QRCode.toString(join, opts))};`,
        '',
      ].join('\n')
    },
    // React's production build embeds a docs URL in its error messages. It is
    // never fetched, but the deck should contain no external URL beyond the
    // ones it shows.
    renderChunk(code) {
      return { code: code.replaceAll('https://react.dev/errors/', 'react.dev/errors/'), map: null }
    },
  }
}

export default defineConfig({
  plugins: [react(), qrPlugin()],
  base: './',
  build: {
    target: 'es2020',
    assetsInlineLimit: 100000,
    modulePreload: { polyfill: false },
  },
})
