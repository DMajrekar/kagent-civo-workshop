import { motion } from 'framer-motion'
import { Slide, Eyebrow, Title, Box, Arrow, ArrowDefs, fadeUp } from '../ui.jsx'

const services = ['web', 'api-gateway', 'checkout', 'orders-db-proxy', 'search', 'image-resizer', 'notifications', 'auth']

export default function PlatformSlide() {
  return (
    <Slide>
      <Eyebrow>The platform</Eyebrow>
      <Title small>Eight services, seven days of logs</Title>

      <div style={{ position: 'absolute', inset: 0 }}>
        <svg width={1920} height={1080} style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
          <ArrowDefs />
          <Arrow from={[1010, 480]} to={[1150, 480]} label="logs" delay={1.6} labelOffset={[0, -18]} labelSize={22} />
          <Arrow from={[1410, 668]} to={[1410, 594]} delay={2.1} />
        </svg>

        {services.map((s, i) => (
          <Box
            key={s}
            x={120 + (i % 2) * 450}
            y={370 + Math.floor(i / 2) * 118}
            w={420}
            h={96}
            title={s}
            delay={0.4 + i * 0.1}
            titleStyle={{ fontFamily: 'var(--mono)', fontSize: 30, fontWeight: 500 }}
          />
        ))}

        <Box x={1150} y={370} w={520} h={220} delay={1.4} title="Loki" titleStyle={{ fontSize: 44 }} />
        <Box x={1150} y={670} w={520} h={150} accent delay={2.0} title="Grafana" titleStyle={{ fontSize: 44 }} />
      </div>

      <motion.p
        className="subtitle"
        style={{ position: 'absolute', left: 120, bottom: 110, maxWidth: 1400 }}
        variants={fadeUp}
        initial="hidden"
        animate="show"
        custom={2.7}
      >
        A small online shop. <span className="accent">Six things are wrong with it.</span> Nobody has looked.
      </motion.p>
    </Slide>
  )
}
