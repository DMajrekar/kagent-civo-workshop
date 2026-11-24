import { Slide, Eyebrow, Title, Box, Arrow, ArrowDefs } from '../ui.jsx'

// How an alert is usually handled, one box at a time. The last box is the
// point of the session: the evidence was in the logs for days before anyone
// was paged.
const steps = [
  { title: 'Alert fires', sub: 'The app is down.' },
  { title: 'Look into logs and monitoring', sub: 'What changed, and when?' },
  { title: 'Put a quick fix in place', sub: 'Find one that works for now.' },
  { title: 'Write up the incident report', sub: 'What happened, and why.' },
]

const X = 120, Y = 400, BW = 372, BH = 210, GAP = 64
const at = (i) => 0.5 + i * 0.7

function Num({ n }) {
  return <div style={{ fontSize: 24, color: 'var(--aurora)', fontWeight: 600, marginBottom: 4 }}>{n}</div>
}

export default function HookSlide() {
  const last = at(steps.length) + 0.3
  return (
    <Slide>
      <Eyebrow>On call</Eyebrow>
      <Title small>What happens when an alert fires</Title>

      <div style={{ position: 'absolute', inset: 0 }}>
        <svg width={1920} height={1080} style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
          <ArrowDefs />
          {steps.slice(1).map((_, i) => {
            const x = X + (i + 1) * (BW + GAP)
            return <Arrow key={i} from={[x - GAP + 4, Y + BH / 2]} to={[x - 4, Y + BH / 2]} delay={at(i + 1) - 0.2} />
          })}
          <Arrow from={[X + 3 * (BW + GAP) + BW / 2, Y + BH + 4]} to={[X + 3 * (BW + GAP) + BW / 2, 716]} delay={last - 0.2} />
        </svg>

        {steps.map((s, i) => (
          <Box
            key={i}
            x={X + i * (BW + GAP)}
            y={Y}
            w={BW}
            h={BH}
            delay={at(i)}
            style={{ justifyContent: 'flex-start', padding: '22px 28px' }}
          >
            <Num n={i + 1} />
            <div className="box-title" style={{ fontSize: 34 }}>{s.title}</div>
            <div className="box-sub" style={{ fontSize: 25, marginTop: 6 }}>{s.sub}</div>
          </Box>
        ))}

        <Box x={X} y={720} w={1680} h={190} accent delay={last} style={{ padding: '22px 36px' }}>
          <Num n={5} />
          <div className="box-title" style={{ fontSize: 44 }}>
            Find out the error has been occurring for <span className="accent">four days</span>, and no one looked
          </div>
        </Box>
      </div>
    </Slide>
  )
}
