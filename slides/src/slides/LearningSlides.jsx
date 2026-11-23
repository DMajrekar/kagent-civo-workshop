import { motion } from 'framer-motion'
import { Slide, Eyebrow, Title, Bullets, fadeUp } from '../ui.jsx'

function Asked({ q, a, delay, accent }) {
  return (
    <motion.div className="panel" style={{ padding: '34px 44px', borderColor: accent ? 'var(--aurora)' : undefined }} variants={fadeUp} initial="hidden" animate="show" custom={delay}>
      <div style={{ fontSize: 44, lineHeight: 1.25 }}>{q}</div>
      <div style={{ fontSize: 34, color: 'var(--cloud)', marginTop: 14 }}>
        <span className="accent">→</span> {a}
      </div>
    </motion.div>
  )
}

export function QuestionSlide() {
  return (
    <Slide>
      <Eyebrow>What we learned</Eyebrow>
      <Title small>The question did the work</Title>
      <div style={{ marginTop: 60, display: 'flex', flexDirection: 'column', gap: 30, maxWidth: 1560 }}>
        <Asked delay={0.5} q="“Is anything about to break?”" a="The crash loop. Everything else looks fine." />
        <Asked
          delay={1.3}
          accent
          q={<>“Is anything about to break <span className="accent">that is not failing today</span>?”</>}
          a="The certificate, with nine days' notice."
        />
      </div>
      <motion.p className="subtitle" style={{ marginTop: 56 }} variants={fadeUp} initial="hidden" animate="show" custom={2.2}>
        Same data. Same model. Same agent.
      </motion.p>
    </Slide>
  )
}

export function CheckWorkSlide() {
  return (
    <Slide>
      <Eyebrow>What we learned</Eyebrow>
      <Title small>Check its work</Title>
      <div style={{ marginTop: 70, maxWidth: 1500 }}>
        <Bullets
          size={44}
          gap={0.3}
          style={{ gap: 44 }}
          items={[
            { text: 'Right finding, wrong service', sub: 'In testing it once pinned the checkout deploy on image-resizer.' },
            { text: 'A fast colleague who has read everything', sub: 'And is sometimes confidently wrong.' },
            { text: 'Make it show you the log line', sub: 'The flag only accepted the answer that was really in the logs.' },
          ]}
        />
      </div>
    </Slide>
  )
}
