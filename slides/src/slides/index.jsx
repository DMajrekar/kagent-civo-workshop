import TitleSlide from './TitleSlide.jsx'
import HookSlide from './HookSlide.jsx'
import PlatformSlide from './PlatformSlide.jsx'
import JoinSlide from './JoinSlide.jsx'
import HowItPlaysSlide from './HowItPlaysSlide.jsx'
import { RoundOneSlide, InterludeSlide, RoundTwoSlide } from './RoundSlides.jsx'
import { AgentIsResourceSlide, McpSlide, Agent1Slide, Agent2Slide, Agent3Slide } from './AgentSlides.jsx'
import ScoreboardSlide from './ScoreboardSlide.jsx'
import { QuestionSlide, CheckWorkSlide } from './LearningSlides.jsx'
import SharingSlide from './SharingSlide.jsx'
import RecapSlide from './RecapSlide.jsx'
import ThanksSlide from './ThanksSlide.jsx'

// The order of play is docs/RUNSHEET.md. The projector is on /board, not on
// this deck, while a round is running: RoundOneSlide and RoundTwoSlide are the
// last thing shown before each clock starts.
//
// JoinSlide must stay at the index named by JOIN_SLIDE in ../event.js.
export const slides = [
  TitleSlide,
  HookSlide,
  PlatformSlide,
  JoinSlide,
  HowItPlaysSlide,
  RoundOneSlide, //        -> /admin: start round 1, projector to /board
  InterludeSlide, //       back from round one
  AgentIsResourceSlide,
  McpSlide,
  Agent1Slide, //          -> make agent-01
  Agent2Slide, //          -> make agent-02
  Agent3Slide, //          -> make agent-03
  RoundTwoSlide, //        -> /admin: start round 2, projector to /board
  ScoreboardSlide, //      back from round two; then show the real /board
  QuestionSlide,
  CheckWorkSlide,
  SharingSlide,
  RecapSlide,
  ThanksSlide,
]
