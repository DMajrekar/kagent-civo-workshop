import { motion } from 'framer-motion'
import { Slide, Eyebrow, Title, Bullets, ease } from '../ui.jsx'
import explore from '../assets/grafana-explore.png'
import time from '../assets/grafana-time.png'

// Three slides on finding your way round Grafana, shown before anyone joins.
// The screenshots are of this hub, taken by scripts/grafana-shots.sh, running
// a dull query on purpose: nothing here gives away an incident.
//
// Highlights are [x, y, width, height] in the screenshot's own 1280x720
// units. scripts/grafana-shots.sh prints them; update these if they move.
const QUERY = [210, 210, 1052, 44]
const RUN = [1106, 85, 84, 46]
const TIME_BUTTON = [999, 85, 77, 46]
const TIME_PANEL = [553, 123, 558, 444]

const W = 1160

function Shot({ src, alt, marks = [] }) {
  return (
    <motion.div
      style={{ position: 'relative', width: W, flex: 'none', borderRadius: 14, overflow: 'hidden', border: '2px solid var(--line)' }}
      initial={{ opacity: 0, y: 24 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.6, ease, delay: 0.3 }}
    >
      <img src={src} alt={alt} style={{ display: 'block', width: '100%' }} />
      {marks.map(([x, y, w, h], i) => (
        <motion.div
          key={i}
          style={{
            position: 'absolute',
            left: `${(x / 1280) * 100}%`,
            top: `${(y / 720) * 100}%`,
            width: `${(w / 1280) * 100}%`,
            height: `${(h / 720) * 100}%`,
            border: '5px solid var(--aurora)',
            borderRadius: 10,
            boxShadow: '0 0 0 4px rgba(0,0,0,0.55), 0 0 36px rgba(0,255,111,0.45)',
          }}
          initial={{ opacity: 0, scale: 1.12 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 0.5, ease, delay: 1.0 + i * 0.5 }}
        />
      ))}
    </motion.div>
  )
}

function GrafanaSlide({ n, title, src, alt, marks, points }) {
  return (
    <Slide>
      <Eyebrow>Grafana · {n} of 3</Eyebrow>
      <Title small>{title}</Title>
      <div style={{ display: 'flex', gap: 56, alignItems: 'flex-start', marginTop: 24 }}>
        <Shot src={src} alt={alt} marks={marks} />
        <Bullets items={points} size={34} start={0.8} gap={0.3} style={{ gap: 34 }} />
      </div>
    </Slide>
  )
}

export const GrafanaExploreSlide = () => (
  <GrafanaSlide
    n={1}
    title="Explore: where you read the logs"
    src={explore}
    alt="Grafana Explore showing a query, a chart of log volume and the log lines"
    points={[
      { text: 'A query at the top', sub: 'Which logs you want.' },
      { text: 'A chart in the middle', sub: 'How many lines, over time.' },
      { text: 'The lines underneath', sub: 'Scroll down to read them.' },
    ]}
  />
)

export const GrafanaQuerySlide = () => (
  <GrafanaSlide
    n={2}
    title="Write a query, then run it"
    src={explore}
    alt="Grafana Explore with the query box and the run button highlighted"
    marks={[QUERY, RUN]}
    points={[
      { text: 'Type in the query box', sub: 'Labels in braces pick the logs.' },
      { text: 'The blue button runs it', sub: 'So does Shift + Enter.' },
      { text: 'Your page has starter queries', sub: 'Tap one, then change it.' },
    ]}
  />
)

export const GrafanaTimeSlide = () => (
  <GrafanaSlide
    n={3}
    title="Choose how far back to look"
    src={time}
    alt="Grafana Explore with the time range menu open"
    marks={[TIME_BUTTON, TIME_PANEL]}
    points={[
      { text: 'The clock opens the time range', sub: 'Pick one from the list on the right.' },
      { text: 'There are seven days of logs', sub: 'Your page opens Grafana on all seven.' },
      { text: 'Narrow it to look closely', sub: 'Or drag across the chart to zoom in.' },
    ]}
  />
)
