import { motion } from 'framer-motion'
import { Slide, Eyebrow, Title, Bullets, fadeUp } from '../ui.jsx'

// Where to take kagent after today. Four ways the same agent could be put to
// work without anyone opening a chat window.
const ideas = [
  { title: 'Connect it to other tools', sub: 'Metrics, traces, tickets, your cloud account. Anything with an MCP server.' },
  { title: 'Run it from a cron job', sub: 'Ask "what got worse this week?" every Monday, before anyone is paged.' },
  { title: 'Manage it with GitOps', sub: 'Agents are manifests. Review them, and let Argo CD or Flux apply them.' },
  { title: 'Start it from an alert', sub: 'When the pager goes off, the first look at the logs is already done.' },
]

export function IdeasSlide() {
  return (
    <Slide>
      <Eyebrow>Where next</Eyebrow>
      <Title small>Other ways to run kagent</Title>
      <div style={{ marginTop: 60, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 32 }}>
        {ideas.map((it, i) => (
          <motion.div key={i} className="panel" style={{ padding: '36px 44px' }} variants={fadeUp} initial="hidden" animate="show" custom={0.5 + i * 0.4}>
            <div style={{ fontSize: 28, color: 'var(--aurora)', fontWeight: 600 }}>{i + 1}</div>
            <div style={{ fontSize: 46, fontWeight: 600, lineHeight: 1.15, margin: '6px 0 12px' }}>{it.title}</div>
            <div style={{ fontSize: 32, color: 'var(--cloud)', lineHeight: 1.3 }}>{it.sub}</div>
          </motion.div>
        ))}
      </div>
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
