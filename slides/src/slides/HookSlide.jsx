import { motion } from 'framer-motion'
import { Slide, fadeUp } from '../ui.jsx'

// Read it aloud, pause on the certificate, then the last line. No explanation
// yet: the room is about to go looking for all three.
const lines = [
  'Checkout started returning 502s four days ago. It lines up with a deploy.',
  'Something exhausts the orders database connection pool every night at 2am.',
  <>
    Also, your auth certificate <span className="accent">expires in nine days</span>.
  </>,
]

export default function HookSlide() {
  return (
    <Slide style={{ justifyContent: 'center' }}>
      <div style={{ maxWidth: 1560 }}>
        {lines.map((l, i) => (
          <motion.p key={i} className="quote" variants={fadeUp} initial="hidden" animate="show" custom={0.3 + i * 1.1}>
            {l}
          </motion.p>
        ))}
      </div>
      <motion.p className="subtitle" style={{ marginTop: 90 }} variants={fadeUp} initial="hidden" animate="show" custom={4.4}>
        Nobody told it to look for any of that.
      </motion.p>
    </Slide>
  )
}
