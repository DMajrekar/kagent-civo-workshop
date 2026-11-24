import { motion } from 'framer-motion'
import { Slide, Eyebrow, Title, Box, Arrow, ArrowDefs, fadeUp } from '../ui.jsx'

// Plain line icons, drawn here so the deck needs no icon library. 24x24 grid.
const icons = {
  user: <><circle cx="12" cy="8" r="4" /><path d="M4.5 20.5c0-4 3.4-6.5 7.5-6.5s7.5 2.5 7.5 6.5" /></>,
  chart: <><path d="M3.5 3.5v17h17" /><path d="M7.5 15.5l3.5-4 3 2.5 4.5-6" /></>,
  logs: <><ellipse cx="12" cy="5.5" rx="7.5" ry="3" /><path d="M4.5 5.5v13c0 1.7 3.4 3 7.5 3s7.5-1.3 7.5-3v-13" /><path d="M4.5 12c0 1.7 3.4 3 7.5 3s7.5-1.3 7.5-3" /></>,
  // Traffic from outside, through a gate, fanned out to what is behind it.
  ingress: <><path d="M2 12h8" /><path d="M7 9l3 3-3 3" /><path d="M12 4v16" /><path d="M14 12h3l4-5M17 12l4 5M17 12h4" /></>,
  app: <><rect x="3" y="4" width="18" height="16" rx="2" /><path d="M3 9h18" /><path d="M6.5 6.6h.01M9.5 6.6h.01" /></>,
  agent: <><rect x="4.5" y="8" width="15" height="11" rx="2.5" /><path d="M12 8V4.5" /><circle cx="12" cy="3.5" r="1" /><path d="M9.5 13v1.5M14.5 13v1.5" /><path d="M2.5 12.5v3M21.5 12.5v3" /></>,
  guard: <><path d="M12 2.5l7.5 3v6c0 4.6-3.1 8.3-7.5 10-4.4-1.7-7.5-5.4-7.5-10v-6z" /><path d="M9 12l2.2 2.2L15.2 10" /></>,
}

function Node({ icon, title, accent, ...box }) {
  return (
    <Box accent={accent} {...box} style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'flex-start', gap: 18 }}>
      <svg width={52} height={52} viewBox="0 0 24 24" fill="none" stroke={accent ? 'var(--aurora)' : 'var(--cloud)'} strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" style={{ flex: 'none' }}>
        {icons[icon]}
      </svg>
      <div className="box-title">{title}</div>
    </Box>
  )
}

const t = { phone: 0.4, ingress: 0.9, ctf: 1.5, ui: 2.1, guard: 2.7, ctrl: 3.3, grafana: 3.9, loki: 4.5 }

export default function SharingSlide() {
  return (
    <Slide>
      <Eyebrow>Behind the curtain</Eyebrow>
      <Title small>One kagent, a room full of strangers</Title>

      <div style={{ position: 'absolute', inset: 0 }}>
        <svg width={1920} height={1080} style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
          <ArrowDefs />
          <Arrow from={[360, 560]} to={[480, 560]} delay={t.ingress - 0.2} />
          <Arrow from={[640, 480]} to={[640, 400]} label="who is this?" delay={t.ctf - 0.2} color="var(--cloud)" dashed labelOffset={[130, 6]} labelSize={22} />
          <Arrow from={[800, 560]} to={[920, 560]} delay={t.ui - 0.2} />
          <Arrow from={[1240, 560]} to={[1340, 560]} delay={t.guard - 0.2} />
          <Arrow from={[1500, 640]} to={[1500, 720]} delay={t.ctrl - 0.2} />
          <Arrow from={[1340, 780]} to={[1244, 780]} label="MCP" delay={t.grafana - 0.2} labelOffset={[0, -18]} labelSize={22} />
          <Arrow from={[720, 640]} to={[960, 718]} delay={t.grafana} color="var(--cloud)" />
          <Arrow from={[920, 780]} to={[804, 780]} delay={t.loki - 0.2} />
        </svg>

        <Node x={120} y={480} w={240} h={160} icon="user" title="User" delay={t.phone} />
        <Node x={480} y={480} w={320} h={160} icon="ingress" title="Ingress" delay={t.ingress} />
        <Node x={480} y={290} w={320} h={110} accent icon="app" title="CTF app" delay={t.ctf} />
        <Node x={920} y={480} w={320} h={160} icon="agent" title="kagent dashboard" delay={t.ui} />
        <Node x={1340} y={480} w={320} h={160} accent icon="guard" title="Guard" delay={t.guard} />
        <Node x={1340} y={720} w={320} h={120} icon="agent" title="kagent controller" delay={t.ctrl} />
        <Node x={920} y={720} w={320} h={120} icon="chart" title="Grafana" delay={t.grafana} />
        <Node x={480} y={720} w={320} h={120} icon="logs" title="Loki" delay={t.loki} />
      </div>

      <motion.p
        className="subtitle"
        style={{ position: 'absolute', left: 120, bottom: 110, maxWidth: 1100, fontSize: 36 }}
        variants={fadeUp}
        initial="hidden"
        animate="show"
        custom={5.0}
      >
        And nothing worth stealing: no Kubernetes tools, no built-in agents. The only tool is the read-only logs.
      </motion.p>
    </Slide>
  )
}
