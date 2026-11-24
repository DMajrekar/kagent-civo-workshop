import { motion } from 'framer-motion'
import { Slide, Eyebrow, Title, Bullets, Code, fadeUp } from '../ui.jsx'

const logql = `{service="checkout"}                 one service
{service="auth", level="warn"}       narrow by level
{env="production"} |= "timeout"      lines containing text

sum by (service) (
  count_over_time({env="production"}[1h])
)                                    how many, per service`

export function RoundOneSlide() {
  return (
    <Slide>
      <Eyebrow>
        <span className="r1">Round one · 20 minutes</span>
      </Eyebrow>
      <Title small>Grafana, and a query box</Title>
      <div className="two-col wide-right" style={{ marginTop: 30, gap: 60 }}>
        <div className="col">
          <Bullets
            size={38}
            items={[
              { text: 'Open Grafana from your page', sub: 'It lands in Explore, on the last seven days.' },
              { text: 'Labels: service, level, env', sub: 'Eight services. Four levels.' },
              { text: 'The logs are in UTC', sub: 'Grafana shows your local time.' },
            ]}
          />
        </div>
        <div className="col">
          <Code delay={0.9} style={{ fontSize: 25 }}>{logql}</Code>
        </div>
      </div>
    </Slide>
  )
}

export function InterludeSlide() {
  return (
    <Slide style={{ justifyContent: 'center' }}>
      <Eyebrow>Time</Eyebrow>
      <motion.h1 className="title" style={{ fontSize: 124, maxWidth: 1500 }} variants={fadeUp} initial="hidden" animate="show" custom={0.2}>
        What did <span className="accent">nobody</span> find?
      </motion.h1>
    </Slide>
  )
}

export function RoundTwoSlide() {
  return (
    <Slide>
      <Eyebrow>
        <span className="r2">Round two · 20 minutes</span>
      </Eyebrow>
      <Title small>Same flags. Now ask.</Title>
      <div style={{ marginTop: 60, maxWidth: 1500 }}>
        <Bullets
          size={42}
          gap={0.3}
          style={{ gap: 40 }}
          items={[
            { text: 'The agents are on your page', sub: 'Each opens the kagent dashboard. Your chats are yours alone.' },
            { text: 'Ask the open question first', sub: '"Has anything got worse this week?" beats "show me the errors".' },
            { text: 'Then ask for the detail the flag wants', sub: 'A version, a job name, an exit code. Make it quote the log line.' },
            { text: 'An answer takes 30 to 60 seconds', sub: 'It is writing and running the queries you were typing by hand.' },
          ]}
        />
      </div>
    </Slide>
  )
}
