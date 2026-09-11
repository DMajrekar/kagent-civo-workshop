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
| *"Is there anything that will fail in the next two weeks but is not failing today?"* | **#5 auth cert expiry**, with a ~9 day ETA — and it correctly sets aside the OOM and the deadlocks as *already* failing | ~79s | verified — **end on this one** |
| *"Is anything about to break that has not broken yet?"* | #3 image-resizer only; claims auth is stable | ~44s | works, but weaker — see below |
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

## The closing prompt, and why the wording matters

*"Is anything about to break that has not broken yet?"* reliably returns the
image-resizer OOM crashloop and asserts everything else is stable — including
`auth`, which by then has 449 certificate warnings. The agent is not being
stupid: an escalating crashloop genuinely is the loudest thing.

Adding **"but is not failing today"** changes the answer completely. The agent
excludes the OOM and the deadlocks *because they are already failing*, and
lands on the certificate with an ETA. Same data, same model — the constraint
in the question is what does the work.

That is worth saying out loud, because it is the most transferable thing in
the whole session: the quality of what you get back is mostly a property of
how you framed the question. Show both versions if you have the time.

Budget ~80 seconds for it. It is the last thing you do, so let it run.

## Known rough edges
- **It sometimes mixes services up.** In one run it attributed checkout's
  `v2.3.0 → v2.3.1` deploy to `image-resizer`. The finding was right, the
  attribution was not. Worth calling out live rather than hoping nobody
  notices — "check its work" is a better lesson than "the agent is always
  right", and it costs you nothing.
- The 7-day window is stated in the agent's system prompt. Without it the
  agent compares week-on-week, finds an empty baseline, and reports that
  everything regressed.
