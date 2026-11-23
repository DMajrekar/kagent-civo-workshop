import { useCallback, useEffect, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { slides } from './slides/index.jsx'
import { Logo, ease } from './ui.jsx'
import { joinQr, joinUrl } from 'virtual:qr'
import { event, JOIN_SLIDE } from './event.js'

const W = 1920
const H = 1080

function readHash() {
  const n = parseInt(window.location.hash.replace('#', ''), 10)
  if (Number.isFinite(n) && n >= 1 && n <= slides.length) return n - 1
  return 0
}

function useScale() {
  const [scale, setScale] = useState(1)
  useEffect(() => {
    const fit = () => setScale(Math.min(window.innerWidth / W, window.innerHeight / H))
    fit()
    window.addEventListener('resize', fit)
    return () => window.removeEventListener('resize', fit)
  }, [])
  return scale
}

export default function Deck() {
  const [index, setIndex] = useState(readHash)
  const [dir, setDir] = useState(1)
  const scale = useScale()
  const typed = useRef('')
  const typedTimer = useRef(null)

  const go = useCallback(
    (next) => {
      const clamped = Math.max(0, Math.min(slides.length - 1, next))
      setIndex((cur) => {
        if (clamped === cur) return cur
        setDir(clamped > cur ? 1 : -1)
        return clamped
      })
    },
    [],
  )

  // Keep the URL hash in sync (1-based) so a reload lands on the same slide.
  useEffect(() => {
    const want = `#${index + 1}`
    if (window.location.hash !== want) window.history.replaceState(null, '', want)
  }, [index])

  useEffect(() => {
    const onHash = () => go(readHash())
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [go])

  useEffect(() => {
    const onKey = (e) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return
      switch (e.key) {
        case 'ArrowRight':
        case 'ArrowDown':
        case 'PageDown':
        case ' ':
        case 'Enter':
          e.preventDefault()
          go(index + 1)
          return
        case 'ArrowLeft':
        case 'ArrowUp':
        case 'PageUp':
        case 'Backspace':
          e.preventDefault()
          go(index - 1)
          return
        case 'Home':
          e.preventDefault()
          go(0)
          return
        case 'End':
          e.preventDefault()
          go(slides.length - 1)
          return
        case 'f':
        case 'F':
          if (document.fullscreenElement) document.exitFullscreen?.()
          else document.documentElement.requestFullscreen?.()
          return
        default:
      }
      // Type a slide number, e.g. "1" "2" then wait, to jump to slide 12.
      if (/^[0-9]$/.test(e.key)) {
        typed.current += e.key
        clearTimeout(typedTimer.current)
        typedTimer.current = setTimeout(() => {
          const n = parseInt(typed.current, 10)
          typed.current = ''
          if (n >= 1 && n <= slides.length) go(n - 1)
        }, 600)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [index, go])

  // Touch: swipe left/right, or tap the right two-thirds for next and the
  // left third for previous. Lets the deck be reviewed on a phone.
  useEffect(() => {
    let startX = 0, startY = 0, startT = 0
    const onStart = (e) => { const t = e.touches[0]; startX = t.clientX; startY = t.clientY; startT = Date.now() }
    const onEnd = (e) => {
      const t = e.changedTouches[0]
      const dx = t.clientX - startX, dy = t.clientY - startY, dt = Date.now() - startT
      if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy)) { go(index + (dx < 0 ? 1 : -1)); return }
      if (Math.abs(dx) < 10 && Math.abs(dy) < 10 && dt < 400) go(index + (t.clientX > window.innerWidth / 3 ? 1 : -1))
    }
    window.addEventListener('touchstart', onStart, { passive: true })
    window.addEventListener('touchend', onEnd, { passive: true })
    return () => { window.removeEventListener('touchstart', onStart); window.removeEventListener('touchend', onEnd) }
  }, [index, go])

  const Current = slides[index]
  // Terminal recordings take the whole stage: nothing drawn over them.
  const chrome = !Current.fullscreen
  const variants = {
    enter: (d) => ({ opacity: 0, x: 80 * d, scale: 0.985 }),
    center: { opacity: 1, x: 0, scale: 1, transition: { duration: 0.55, ease } },
    exit: (d) => ({ opacity: 0, x: -80 * d, scale: 0.985, transition: { duration: 0.35, ease } }),
  }

  return (
    <div className="viewport">
      <div className="stage" style={{ transform: `translate(-50%, -50%) scale(${scale})` }}>
        <AnimatePresence mode="wait" custom={dir} initial={false}>
          <motion.div
            key={index}
            className="slide-layer"
            custom={dir}
            variants={variants}
            initial="enter"
            animate="center"
            exit="exit"
          >
            <Current />
          </motion.div>
        </AnimatePresence>

        {chrome && index !== 0 && (
          <div className="chrome-logo">
            <Logo height={30} />
            {event.name && <span>{event.name}</span>}
          </div>
        )}
        {/* Latecomers: the join code stays in the corner once it has been shown. */}
        {chrome && index > JOIN_SLIDE && index < slides.length - 1 && (
          <div className="chrome-qr" title={joinUrl}>
            <div className="chrome-qr-code" dangerouslySetInnerHTML={{ __html: joinQr }} />
            <div className="chrome-qr-label">join</div>
          </div>
        )}
        {chrome && (
          <>
            <div className="counter">
              {index + 1} / {slides.length}
            </div>
            <div className="progress-track" />
            <motion.div
              className="progress"
              initial={false}
              animate={{ width: `${((index + 1) / slides.length) * 100}%` }}
              transition={{ duration: 0.45, ease }}
            />
          </>
        )}
      </div>
    </div>
  )
}
