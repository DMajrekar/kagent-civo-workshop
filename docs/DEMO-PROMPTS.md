# Verified demo prompts

Measured against the seeded dataset with `RELAX_MODEL=DeepSeek-V4-Pro`. Use
these on stage; they are the ones that actually land.

**Do not improvise prompts live.** The difference between a question that finds
the planted incident and one that produces a shrug is larger than it looks, and
you will not get it back in a 60-minute session.

| Prompt | Finds | Time | Confidence |
|--------|-------|------|-----------|
| *"Has anything got worse in the last week?"* | #1 checkout 502s after the v2.3.1 deploy, **and** #3 image-resizer OOM climbing | ~33s | verified, reliable |
| *"Are there any problems that happen on a schedule?"* | #2 orders-db-proxy nightly pool exhaustion, with a correct root-cause narrative about a nightly batch job | ~51s | verified, reliable |
| *"Is anything about to break that has not broken yet?"* | #3 image-resizer, framed as a precursor to failure | ~44s | verified, but see below |
| *"Where is our log volume going?"* | #4 notifications debug spam | — | dataset verified, prompt not yet timed |
| *"Which service is least healthy right now?"* | #3 image-resizer | — | dataset verified, prompt not yet timed |

## Model choice: DeepSeek-V4-Pro, not Llama

Both pass the tool-calling probe. Only one finds the incidents.

- **Llama-4-Maverick** (6–9s) missed the checkout regression entirely, blamed
  `notifications` on an artifact, and gave a confidently wrong answer about
  scheduling. Fast and wrong.
- **DeepSeek-V4-Pro** (30–60s) found incidents 1, 2 and 3 correctly and
  specifically, with plausible root causes.

Thirty to sixty seconds of thinking is a long silence on stage. Fill it: that
is the natural moment to explain what the agent is actually doing — which
tools it is calling, and that the LogQL is being written by the model, not by
you. The wait is content if you use it.

## Known rough edges

- **Cert expiry (#5) does not surface** from the open "about to break"
  question — the agent reaches for the OOM crashloop instead, which is a
  defensible answer. If you want #5 on stage, ask directly: *"Are there any
  warnings about certificates or credentials expiring?"*
- **It sometimes mixes services up.** In one run it attributed checkout's
  `v2.3.0 → v2.3.1` deploy to `image-resizer`. The finding was right, the
  attribution was not. Worth calling out live rather than hoping nobody
  notices — "check its work" is a better lesson than "the agent is always
  right", and it costs you nothing.
- The 7-day window is stated in the agent's system prompt. Without it the
  agent compares week-on-week, finds an empty baseline, and reports that
  everything regressed.
