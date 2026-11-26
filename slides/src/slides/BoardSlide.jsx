import { useEffect } from 'react'
import { Slide } from '../ui.jsx'
import { joinQr, joinUrl } from 'virtual:qr'

// The live scoreboard, framed in the deck, so the projector never has to leave
// it. It is the CTF app's own /board page and keeps itself up to date.
//
// The page is laid out for a browser window, not a 1920px stage, so it is
// drawn at 1280x720 and scaled up by half: the same picture, readable from
// the back of the room.
const SCALE = 1.5

function Board({ join }) {
  // A click inside the frame would take the keyboard with it, and the arrow
  // keys would stop turning slides. Take it straight back. The mouse wheel
  // still scrolls the board when the room is bigger than the screen.
  useEffect(() => {
    const back = () => setTimeout(() => window.focus(), 0)
    window.addEventListener('blur', back)
    return () => window.removeEventListener('blur', back)
  }, [])

  return (
    <Slide style={{ padding: 0, background: 'var(--black)' }}>
      <iframe
        src={`${joinUrl}/board?embed`}
        title="Scoreboard"
        tabIndex={-1}
        style={{
          width: 1920 / SCALE,
          height: 1080 / SCALE,
          border: 0,
          transform: `scale(${SCALE})`,
          transformOrigin: '0 0',
          background: 'var(--black)',
        }}
      />
      {join && (
        <div className="chrome-qr" style={{ bottom: 40 }} title={joinUrl}>
          <div className="chrome-qr-code" dangerouslySetInnerHTML={{ __html: joinQr }} />
          <div className="chrome-qr-label">join</div>
        </div>
      )}
    </Slide>
  )
}

// One component per place the board appears. `join` keeps the join code in
// the corner for latecomers; `fullscreen` hides the deck's own chrome.
export function board({ join = true } = {}) {
  const C = () => <Board join={join} />
  C.fullscreen = true
  return C
}
