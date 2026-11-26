import { motion } from 'framer-motion'
import { Slide, Eyebrow, Title, fadeUp } from '../ui.jsx'

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
