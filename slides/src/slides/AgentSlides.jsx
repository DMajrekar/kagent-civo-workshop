import { motion } from 'framer-motion'
import { Slide, Eyebrow, Title, Bullets, Chip, Code, Box, Arrow, ArrowDefs, fadeUp } from '../ui.jsx'

export function AgentIsResourceSlide() {
  const rows = [
    ['ModelConfig', 'what it thinks with'],
    ['Agent', 'what it is for, and what it may touch'],
    ['RemoteMCPServer', 'where its tools come from'],
  ]
  return (
    <Slide>
      <Eyebrow>kagent</Eyebrow>
      <Title small>An agent is a Kubernetes resource</Title>
      <div style={{ marginTop: 70, display: 'flex', flexDirection: 'column', gap: 26, maxWidth: 1500 }}>
        {rows.map(([kind, what], i) => (
          <motion.div
            key={kind}
            className="panel"
            style={{ display: 'flex', alignItems: 'baseline', gap: 40, padding: '30px 44px' }}
            variants={fadeUp}
            initial="hidden"
            animate="show"
            custom={0.5 + i * 0.35}
          >
            <div style={{ fontFamily: 'var(--mono)', fontSize: 40, color: 'var(--aurora)', width: 470, flex: 'none' }}>{kind}</div>
            <div style={{ fontSize: 40, color: 'var(--cloud)' }}>{what}</div>
          </motion.div>
        ))}
      </div>
      <motion.p className="subtitle" style={{ marginTop: 56 }} variants={fadeUp} initial="hidden" animate="show" custom={1.9}>
        A manifest. Review it, diff it, roll it back.
      </motion.p>
    </Slide>
  )
}

export function McpSlide() {
  return (
    <Slide>
      <Eyebrow>MCP</Eyebrow>
      <Title small>Tools an agent finds for itself</Title>

      <div style={{ position: 'absolute', inset: 0 }}>
        <svg width={1920} height={1080} style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
          <ArrowDefs />
          <Arrow from={[520, 520]} to={[700, 520]} label="what can you do?" delay={0.9} labelOffset={[0, -22]} labelSize={22} />
          <Arrow from={[1080, 520]} to={[1240, 520]} delay={1.5} />
          <Arrow from={[1460, 600]} to={[1460, 680]} delay={2.0} />
        </svg>
        <Box x={120} y={430} w={400} h={180} accent title="Agent" sub="a model, a prompt, a tool list" delay={0.4} titleStyle={{ fontSize: 40 }} />
        <Box x={700} y={430} w={380} h={180} title="MCP server" sub="read-only, six tools" delay={1.0} titleStyle={{ fontSize: 40 }} />
        <Box x={1240} y={440} w={440} h={160} title="Grafana" sub="the same one you just used" delay={1.6} titleStyle={{ fontSize: 40 }} />
        <Box x={1240} y={680} w={440} h={130} title="Loki" sub="seven days of logs" delay={2.1} titleStyle={{ fontSize: 40 }} />
      </div>

      <motion.p
        className="subtitle"
        style={{ position: 'absolute', left: 120, bottom: 110, maxWidth: 1050 }}
        variants={fadeUp}
        initial="hidden"
        animate="show"
        custom={2.6}
      >
        The agent has no idea what Loki is. It connects, asks what tools exist, and decides which to use.
      </motion.p>
    </Slide>
  )
}

// One slide per agent, shown just before its `make` target is run. The left
// column is the argument; the right is the part of the manifest that makes it.
function AgentSlide({ n, name, title, points, code, codeSize = 24 }) {
  return (
    <Slide>
      <Eyebrow>
        Agent {n} of 3 <span className="muted">· {name}</span>
      </Eyebrow>
      <Title small>{title}</Title>
      <div className="two-col wide-right" style={{ marginTop: 20, gap: 60, alignItems: 'start', paddingTop: 30 }}>
        <div className="col">
          <Bullets items={points} size={38} />
          <Chip delay={1.6} style={{ marginTop: 50 }}>make agent-0{n}</Chip>
        </div>
        <div className="col">
          <Code delay={0.7} style={{ fontSize: codeSize }}>{code}</Code>
        </div>
      </div>
    </Slide>
  )
}

const hl = (s) => <span className="hl">{s}</span>

export const Agent1Slide = () => (
  <AgentSlide
    n={1}
    name="log-reader"
    title="Tools, and almost no briefing"
    points={[
      { text: 'The agent you would write in five minutes', sub: 'A model, three tools, three lines of prompt.' },
      { text: 'Good at a direct question', sub: 'Lost on an open one.' },
    ]}
    code={
      <>
        {'kind: Agent\nmetadata:\n  name: log-reader\nspec:\n  declarative:\n    modelConfig: default-model-config\n    systemMessage: |\n'}
        {hl('      You answer questions about\n      application logs stored in Loki.\n')}
        {'    tools:\n      - mcpServer:\n          name: workshop-logs\n          toolNames:\n            - list_loki_label_names\n            - list_loki_label_values\n            - query_loki_logs'}
      </>
    }
  />
)

export const Agent2Slide = () => (
  <AgentSlide
    n={2}
    name="log-detective"
    title="Same model. Better briefing."
    codeSize={23}
    points={[
      { text: 'Everything new is in the prompt', sub: 'What the data looks like, and how to look at it.' },
      { text: 'Count before you read', sub: 'A trend is invisible one line at a time.' },
    ]}
    code={
      <>
        {'systemMessage: |\n'}
        {hl('  There are exactly 7 days of history.\n')}
        {'  Do not compare against "the week\n  before": there is nothing there.\n\n'}
        {hl('  Use aggregate LogQL to find patterns.\n')}
        {'  Reading individual lines will not\n  reveal a trend.\n\n'}
        {hl('  Then read a few of the actual lines\n  and quote the exact text.\n')}
        {'\n  Say plainly when you found nothing.'}
      </>
    }
  />
)

export const Agent3Slide = () => (
  <AgentSlide
    n={3}
    name="early-warning"
    title="A specialist: ignore the fires"
    points={[
      { text: 'A general agent goes to whatever is loudest', sub: 'Which is whatever is already broken.' },
      { text: 'This one looks for what has not failed yet', sub: 'Countdowns. Numbers that creep.' },
    ]}
    code={
      <>
        {'systemMessage: |\n'}
        {hl('  Ignore anything that is already\n  failing. Errors are someone else\'s job.\n')}
        {'\n  Your job is the quiet things:\n  - Warnings that mention a deadline,\n    an expiry, a limit or a countdown.\n  - Numbers inside log lines that drift\n    in one direction, day over day,\n    while the service logs no errors.'}
      </>
    }
  />
)
