import { motion } from 'framer-motion'
import { Slide, Eyebrow, Title, fadeUp, stagger, item, ease } from '../ui.jsx'
import { joinQr, joinUrl } from 'virtual:qr'

const steps = [
  { text: 'Scan the code', sub: 'Mobile data is fine. There is nothing to install.' },
  { text: 'Enter your email', sub: 'The scoreboard shows a made-up handle, never your address.' },
  { text: 'Keep the page open', sub: 'The flags appear on it when the first round starts.' },
]

export default function JoinSlide() {
  return (
    <Slide>
      <Eyebrow>Join in</Eyebrow>
      <Title small>All you need is a phone</Title>
      <div className="two-col" style={{ marginTop: 20 }}>
        <motion.div className="col" variants={stagger(0.3, 0.5)} initial="hidden" animate="show" style={{ display: 'flex', flexDirection: 'column', gap: 44 }}>
          {steps.map((s, i) => (
            <motion.div key={i} variants={item} style={{ display: 'flex', gap: 30, alignItems: 'flex-start' }}>
              <div className="step-num">{i + 1}</div>
              <div>
                <div style={{ fontSize: 46, lineHeight: 1.2 }}>{s.text}</div>
                <div className="muted" style={{ fontSize: 30, marginTop: 6 }}>{s.sub}</div>
              </div>
            </motion.div>
          ))}
        </motion.div>
        <div className="col" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 28 }}>
          <motion.div
            className="big-qr"
            style={{ width: 560, height: 560 }}
            initial={{ opacity: 0, scale: 0.85, rotate: -3 }}
            animate={{ opacity: 1, scale: 1, rotate: 0 }}
            transition={{ duration: 0.7, ease, delay: 0.4 }}
            // QR SVG generated at build time by vite.config.js; no runtime fetch.
            dangerouslySetInnerHTML={{ __html: joinQr }}
          />
          <motion.div style={{ fontFamily: 'var(--mono)', fontSize: 30, color: 'var(--cloud)' }} variants={fadeUp} initial="hidden" animate="show" custom={0.9}>
            {joinUrl.replace('https://', '')}
          </motion.div>
        </div>
      </div>
    </Slide>
  )
}
