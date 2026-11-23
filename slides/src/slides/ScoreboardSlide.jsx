import { motion } from 'framer-motion'
import { Slide, Eyebrow, Title, Bullets, ease } from '../ui.jsx'

// An illustration of the pattern to look for, not live data: the real
// scoreboard is the next thing on the projector. 0 unsolved, 1 Grafana,
// 2 kagent; twelve flags, easiest on the left.
const rows = [
  [1, 1, 1, 1, 2, 1, 2, 2, 2, 2, 2, 2],
  [1, 1, 1, 2, 2, 1, 1, 2, 2, 2, 2, 0],
  [1, 1, 1, 1, 1, 1, 2, 2, 0, 2, 0, 2],
  [1, 1, 2, 2, 0, 1, 2, 2, 2, 0, 2, 0],
  [1, 0, 1, 2, 2, 2, 0, 2, 2, 0, 0, 2],
]

export default function ScoreboardSlide() {
  return (
    <Slide>
      <Eyebrow>The scoreboard</Eyebrow>
      <Title small>Read the colours, not the ranking</Title>
      <div className="two-col" style={{ marginTop: 20, gap: 70 }}>
        <div className="col">
          <Bullets
            size={38}
            items={[
              { text: <><span className="r1">Blue on the left</span></>, sub: 'Grafana is good at "which service is loudest". The agent did not make that easier.' },
              { text: <><span className="r2">Orange on the right</span></>, sub: 'A slowdown with no errors. A certificate that has not expired yet.' },
              { text: 'Round two had a head start', sub: 'You had already spent twenty minutes with the data.' },
            ]}
          />
        </div>
        <motion.div className="col panel" style={{ padding: 40 }} initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5, ease, delay: 0.4 }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
            {rows.map((r, i) => (
              <div key={i} style={{ display: 'flex', gap: 12 }}>
                {r.map((v, j) => (
                  <motion.div
                    key={j}
                    className={`dot ${v ? `d${v}` : ''}`}
                    initial={{ scale: 0 }}
                    animate={{ scale: 1 }}
                    transition={{ duration: 0.3, ease, delay: (v === 2 ? 2.2 : 0.8) + j * 0.06 + i * 0.05 }}
                  />
                ))}
              </div>
            ))}
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 22, fontSize: 22, color: 'var(--dim)' }}>
            <span>easiest flag</span>
            <span>hardest flag</span>
          </div>
        </motion.div>
      </div>
    </Slide>
  )
}
