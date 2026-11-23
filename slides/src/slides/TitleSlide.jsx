import { motion } from 'framer-motion'
import { Slide, Logo, fadeUp, ease } from '../ui.jsx'
import { event } from '../event.js'
import dinesh from '../assets/dinesh.png'

export default function TitleSlide() {
  return (
    <Slide style={{ justifyContent: 'space-between' }}>
      {/* Soft aurora glow, pure CSS, no assets. */}
      <motion.div
        aria-hidden
        style={{
          position: 'absolute',
          right: -300,
          top: -200,
          width: 1100,
          height: 1100,
          borderRadius: '50%',
          background: 'radial-gradient(closest-side, rgba(0,255,111,0.22), rgba(0,255,111,0.06) 55%, transparent 72%)',
          pointerEvents: 'none',
        }}
        initial={{ opacity: 0, scale: 0.8 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ duration: 1.6, ease }}
      />
      <motion.div variants={fadeUp} initial="hidden" animate="show" custom={0}>
        <Logo height={64} />
      </motion.div>

      <div style={{ maxWidth: 1500 }}>
        <motion.h1
          className="title"
          style={{ fontSize: 132, marginBottom: 40 }}
          variants={fadeUp}
          initial="hidden"
          animate="show"
          custom={0.2}
        >
          Your cluster called.
          <br />
          <span className="accent">It has found a problem.</span>
        </motion.h1>
        <motion.p className="subtitle" variants={fadeUp} initial="hidden" animate="show" custom={0.5}>
          A capture-the-flag in a week of production logs. Bring a phone.
        </motion.p>
      </div>

      <motion.div
        style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', fontSize: 34, color: 'var(--cloud)' }}
        variants={fadeUp}
        initial="hidden"
        animate="show"
        custom={0.8}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 24 }}>
          <img
            src={dinesh}
            alt={event.speaker}
            width={80}
            height={80}
            style={{ width: 80, height: 80, borderRadius: '50%', objectFit: 'cover', border: '3px solid var(--aurora)', display: 'block' }}
          />
          <div>
            <div style={{ color: 'var(--white)', fontWeight: 600 }}>{event.speaker}</div>
            <div className="muted">{event.org}</div>
          </div>
        </div>
        <div style={{ textAlign: 'right' }}>
          <div style={{ color: 'var(--white)' }}>{event.name}</div>
          <div className="muted">{event.where}</div>
        </div>
      </motion.div>
    </Slide>
  )
}
