import { motion } from 'framer-motion'
import { Slide, Eyebrow, Title, fadeUp, ease } from '../ui.jsx'

function Round({ color, label, tool, note, delay }) {
  return (
    <motion.div
      className="panel"
      style={{ flex: 1, borderColor: color, padding: '44px 48px' }}
      initial={{ opacity: 0, y: 24 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.6, ease, delay }}
    >
      <div style={{ fontSize: 30, color }}>{label}</div>
      <div style={{ fontSize: 84, fontWeight: 600, letterSpacing: '-0.02em', margin: '10px 0 14px' }}>{tool}</div>
      <div style={{ fontSize: 34, color: 'var(--cloud)', lineHeight: 1.3 }}>{note}</div>
    </motion.div>
  )
}

export default function HowItPlaysSlide() {
  return (
    <Slide>
      <Eyebrow>How it plays</Eyebrow>
      <Title small>Twelve flags. Two rounds. One scoreboard.</Title>
      <div style={{ display: 'flex', alignItems: 'stretch', gap: 36, marginTop: 70 }}>
        <Round color="var(--r1)" label="Round one · 10 minutes" tool="Grafana" note="The logs and a query box. Find what you can." delay={0.5} />
        <motion.div
          style={{ alignSelf: 'center', fontSize: 72, color: 'var(--dim)' }}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 1.2 }}
        >
          →
        </motion.div>
        <Round color="var(--r2)" label="Round two · 15 minutes" tool="kagent" note="The same logs, and agents to ask. Carry on where you stopped." delay={1.4} />
      </div>
      <motion.p className="subtitle" style={{ marginTop: 64, maxWidth: 1450 }} variants={fadeUp} initial="hidden" animate="show" custom={2.2}>
        Same flags in both rounds. Each one you solve is marked with the round it fell in.
      </motion.p>
    </Slide>
  )
}
