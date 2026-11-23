import { Slide, Eyebrow, Title, Bullets } from '../ui.jsx'

export default function RecapSlide() {
  return (
    <Slide>
      <Eyebrow>Take this home</Eyebrow>
      <Title>What to take away</Title>
      <div style={{ marginTop: 80, maxWidth: 1560 }}>
        <Bullets
          size={46}
          gap={0.3}
          style={{ gap: 44 }}
          items={[
            { text: 'Nothing was hidden from Grafana', sub: 'The difference was knowing what to ask, and asking it quickly.' },
            { text: 'An agent is a manifest', sub: 'A model, a prompt and a tool list. The prompt is most of it.' },
            { text: 'Give it less than you think', sub: 'Read-only tools, one job, and a person who checks the answer.' },
          ]}
        />
      </div>
    </Slide>
  )
}
