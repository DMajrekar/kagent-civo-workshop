import { motion } from 'framer-motion'
import { Slide, Eyebrow, Title, Box, Arrow, ArrowDefs, fadeUp } from '../ui.jsx'

const t = { phone: 0.4, ingress: 0.9, ctf: 1.5, ui: 2.1, guard: 2.7, ctrl: 3.3 }

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
        </svg>

        <Box x={120} y={480} w={240} h={160} title="A phone" sub="mobile data" delay={t.phone} />
        <Box x={480} y={480} w={320} h={160} title="Ingress" sub="asks before every request" delay={t.ingress} />
        <Box x={480} y={290} w={320} h={110} accent title="CTF app" sub="names the player" delay={t.ctf} />
        <Box x={920} y={480} w={320} h={160} title="kagent dashboard" sub="the real one" delay={t.ui} />
        <Box x={1340} y={480} w={320} h={160} accent title="Guard" sub="chat passes, edits do not" delay={t.guard} />
        <Box x={1340} y={720} w={320} h={120} title="kagent controller" sub="chats kept per player" delay={t.ctrl} />
      </div>

      <motion.p
        className="subtitle"
        style={{ position: 'absolute', left: 120, bottom: 110, maxWidth: 1100, fontSize: 36 }}
        variants={fadeUp}
        initial="hidden"
        animate="show"
        custom={3.8}
      >
        And nothing worth stealing: no Kubernetes tools, no built-in agents. The only tool is the read-only logs.
      </motion.p>
    </Slide>
  )
}
