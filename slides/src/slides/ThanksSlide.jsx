import { motion } from 'framer-motion'
import { Slide, Logo, fadeUp, ease } from '../ui.jsx'
import { repoQr, repoUrl } from 'virtual:qr'
import { event } from '../event.js'
import dinesh from '../assets/dinesh.png'

export default function ThanksSlide() {
  const shownUrl = repoUrl.replace('https://', '')
  return (
    <Slide style={{ justifyContent: 'center' }}>
      <div className="two-col" style={{ flex: 'none', alignItems: 'center' }}>
        <div className="col">
          <motion.h1 className="title" style={{ fontSize: 120, marginBottom: 36 }} variants={fadeUp} initial="hidden" animate="show" custom={0.1}>
            Thank you.
            <br />
            <span className="accent">Go and ask yours.</span>
          </motion.h1>
          <motion.p className="subtitle" variants={fadeUp} initial="hidden" animate="show" custom={0.5}>
            The hub, the flags and all three agents are in the repo.
          </motion.p>
          <motion.div
            style={{ marginTop: 56, display: 'flex', alignItems: 'center', gap: 28, fontSize: 32, color: 'var(--cloud)' }}
            variants={fadeUp}
            initial="hidden"
            animate="show"
            custom={0.8}
          >
            <img
              src={dinesh}
              alt={event.speaker}
              width={140}
              height={140}
              style={{ width: 140, height: 140, borderRadius: '50%', objectFit: 'cover', border: '3px solid var(--aurora)', display: 'block', flex: 'none' }}
            />
            <div>
              <div style={{ color: 'var(--white)', fontWeight: 600 }}>{event.speaker}</div>
              <div className="muted">{event.org}</div>
              <div style={{ marginTop: 20 }}>
                <Logo height={44} />
              </div>
            </div>
          </motion.div>
        </div>
        <div className="col" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 24 }}>
          <motion.div
            className="big-qr"
            style={{ width: 480, height: 480 }}
            initial={{ opacity: 0, scale: 0.85, rotate: -3 }}
            animate={{ opacity: 1, scale: 1, rotate: 0 }}
            transition={{ duration: 0.7, ease, delay: 0.4 }}
            // QR SVG generated at build time by vite.config.js; no runtime fetch.
            dangerouslySetInnerHTML={{ __html: repoQr }}
          />
          <motion.div style={{ textAlign: 'center' }} variants={fadeUp} initial="hidden" animate="show" custom={0.9}>
            <div style={{ fontSize: 28, fontWeight: 600 }}>The repo</div>
            <div style={{ fontFamily: 'var(--mono)', fontSize: 24, color: 'var(--cloud)', marginTop: 6 }}>{shownUrl}</div>
          </motion.div>
        </div>
      </div>
    </Slide>
  )
}
