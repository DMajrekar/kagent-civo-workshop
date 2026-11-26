import { useEffect, useState } from 'react'
import { Slide } from '../ui.jsx'

// Recorded terminal sessions, made by scripts/record.sh and found by name.
// A glob rather than an import per file, so the deck still builds before the
// recordings exist: a missing one shows a note on its slide instead.
const recordings = import.meta.glob('../assets/demo-kagent-*.gif', { eager: true, query: '?url', import: 'default' })
const urlFor = (n) => recordings[`../assets/demo-kagent-${n}.gif`]

// Each GIF plays once (agg --no-loop) and holds its last frame. Every visit to
// the slide hands the <img> a fresh object URL, so it restarts from frame one.
const cache = new Map()
async function load(url) {
  if (!cache.has(url)) cache.set(url, fetch(url).then((r) => r.blob()))
  return cache.get(url)
}
Object.values(recordings).forEach((u) => load(u).catch(() => {}))

function Recording({ n, title }) {
  const gif = urlFor(n)
  const [src, setSrc] = useState(null)
  useEffect(() => {
    if (!gif) return undefined
    let obj
    load(gif).then((blob) => { obj = URL.createObjectURL(blob); setSrc(obj) }).catch(() => setSrc(gif))
    return () => { if (obj) URL.revokeObjectURL(obj) }
  }, [gif])

  // Edge to edge: no padding, no deck chrome (see `fullscreen` below). The
  // recording is black-backgrounded, so any letterboxing is invisible.
  return (
    <Slide style={{ padding: 0, background: 'var(--black)' }}>
      {gif ? (
        src && (
          // No fade of its own: between two recordings the change is a cut.
          <img
            src={src}
            alt={`Terminal recording: ${title}`}
            style={{ width: '100%', height: '100%', objectFit: 'contain', display: 'block' }}
          />
        )
      ) : (
        <div style={{ margin: 'auto', textAlign: 'center' }}>
          <div className="eyebrow">Recording {n} · {title}</div>
          <div className="subtitle">Not recorded yet.</div>
          <div className="chip" style={{ marginTop: 40 }}>
            <span className="prompt">$</span>
            <span>make record</span>
          </div>
        </div>
      )}
    </Slide>
  )
}

// One component per recording. `fullscreen` tells Deck.jsx to hide the logo,
// counter, join code and progress bar while it is up.
export function demo(n, title) {
  const C = () => <Recording n={n} title={title} />
  C.fullscreen = true
  return C
}
