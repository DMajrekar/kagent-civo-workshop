import TitleSlide from './TitleSlide.jsx'
import HookSlide from './HookSlide.jsx'
import PlatformSlide from './PlatformSlide.jsx'
import JoinSlide from './JoinSlide.jsx'
import HowItPlaysSlide from './HowItPlaysSlide.jsx'
import { GrafanaExploreSlide, GrafanaQuerySlide, GrafanaTimeSlide } from './GrafanaSlides.jsx'
import { RoundOneSlide, InterludeSlide, RoundTwoSlide } from './RoundSlides.jsx'
import { AgentIsResourceSlide, McpSlide, InstallSlide, SetupSlide, Agent1Slide, Agent2Slide, Agent3Slide } from './AgentSlides.jsx'
import ScoreboardSlide from './ScoreboardSlide.jsx'
import { IdeasSlide, CheckWorkSlide } from './LearningSlides.jsx'
import SharingSlide from './SharingSlide.jsx'
import RecapSlide from './RecapSlide.jsx'
import ThanksSlide from './ThanksSlide.jsx'
import { demo } from './DemoSlide.jsx'

// Full-screen terminal recordings of the build, made by `make record`.
// The hub is already built when the room arrives; these are how the deck shows
// it being built anyway.
// The cluster and the install are each one recording cut into a slide per
// section, so each can be talked over for as long as it needs. If `make
// record` reports a different number of parts, change these lists to match.
const DemoCluster = [
  demo('0-1', 'A new cluster, from Terraform'),
  demo('0-2', 'What a new cluster is running'),
]
const DemoInstall = [
  demo('1-1', 'The kagent CRDs and the model key'),
  demo('1-2', 'kagent itself'),
  demo('1-3', 'What is running'),
  demo('1-4', 'Connecting the logs'),
]
const DemoAgent1 = demo(2, 'log-reader')
const DemoAgent2 = demo(3, 'log-detective')
const DemoAgent3 = demo(4, 'early-warning')

// The order of play is docs/RUNSHEET.md. The projector is on /board, not on
// this deck, while a round is running: RoundOneSlide and RoundTwoSlide are the
// last thing shown before each clock starts.
//
// The small join code in the corner appears on every slide after JoinSlide.
export const slides = [
  TitleSlide,
  HookSlide,
  PlatformSlide,
  HowItPlaysSlide,
  GrafanaExploreSlide,
  GrafanaQuerySlide,
  GrafanaTimeSlide,
  JoinSlide,
  RoundOneSlide, //        -> /admin: start round 1, projector to /board
  InterludeSlide, //       back from round one
  AgentIsResourceSlide,
  McpSlide,
  InstallSlide,
  ...DemoCluster, //       recordings: terraform apply, then an empty cluster
  ...DemoInstall, //       recordings: hub-08, a slide per section
  SetupSlide,
  Agent1Slide,
  DemoAgent1, //           recording: agent-01
  Agent2Slide,
  DemoAgent2, //           recording: agent-02
  Agent3Slide,
  DemoAgent3, //           recording: agent-03
  RoundTwoSlide, //        -> /admin: start round 2, projector to /board
  ScoreboardSlide, //      back from round two; then show the real /board
  IdeasSlide,
  CheckWorkSlide,
  SharingSlide,
  RecapSlide,
  ThanksSlide,
]

export const JOIN_SLIDE = slides.indexOf(JoinSlide)
