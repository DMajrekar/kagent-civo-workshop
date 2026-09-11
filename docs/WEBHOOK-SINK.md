# Webhook sink ("the wall")

A small app on the hub that receives each attendee's daily-report CronJob output
and displays it on a page they can keep open. Replaces the Slack/Discord webhook
idea: nothing to set up, works on a phone, and gives the room a shared finale.

## Flow

1. Attendee opens `https://hub.<domain>/` and clicks **Get my code**.
2. They get a code — word-pair form, e.g. `amber-otter`. Word pairs, not hex:
   people read these aloud and type them from a projector, and `a3f9` becomes
   `a3f4` every single time.
3. They put it in `.env` as `REPORT_WEBHOOK_URL=https://hub.<domain>/hook/amber-otter`.
4. Step-05's CronJob POSTs its report there.
5. Their page (`/c/amber-otter`) live-updates with each delivery.

Step-05 triggers the job manually (`kubectl create job --from=cronjob/...`) so
they see their report land within seconds rather than waiting until tomorrow.

## The wall

`/wall` — instructor view, every code, newest first, auto-scrolling. Put it on
the projector during step-05 and the room watches 25 agent-written incident
reports arrive one by one. This is the moment people photograph.

Worth adding: a count of distinct incidents mentioned across all reports. Since
the seeded dataset has six known answers (see INCIDENTS.md), you can show that
different agents found different things — which is a much more interesting
teaching point than everyone getting identical output.

## Build notes

Single container, no database.

- `POST /hook/:code` — accept any content type, buffer it, return 204
- `GET /c/:code` — HTML page, live via SSE (poll fallback for hostile WiFi)
- `GET /api/c/:code` — JSON, for the curious
- `GET /wall` — every key the server has seen a delivery for
- Minting a code needs no endpoint at all — the page generates a word pair
  client-side and writes it to `localStorage`. Collisions don't matter much
  (two people would share a page), but generate from a ~2000-word list and
  check against nothing; at 25 attendees the birthday odds are negligible.

Storage: **none on the server.** No database, no PVC, no volume.

The trick is that a code is never *registered* — it's an opaque routing key,
not a record. `POST /hook/<anything>` is accepted and buffered under that key.
Nothing to invalidate, so a pod restart can't break anyone's `.env`; their
CronJob keeps posting to the same URL and it keeps working.

- **Server:** in-memory ring buffer, last 30 deliveries per key. A month of
  dailies is ~30, so that's the full history while it's up. Cap the number of
  live keys so a loop can't exhaust memory. Total footprint is kilobytes.
- **Browser:** the page keeps the code *and* an append-only archive of
  deliveries it has already seen in `localStorage`, and renders the merge of
  that archive with whatever the server currently holds. History then lives on
  the attendee's machine and survives hub restarts entirely.
- `replicas: 1`, no volumes, `emptyDir` if it needs scratch at all.

Wrap every `localStorage` read and write in try/catch — it throws outright in
a private window and in some locked-down corporate browser profiles, and a
page that white-screens on a projector because storage was blocked is a bad
minute. Fall back to server-only rendering when it's unavailable.

## Guard rails

This is a **public unauthenticated write endpoint** on your hub, announced to a
room full of people who have just been taught to automate things. Non-optional:

- **Escape everything on render.** The body is attacker-controlled text and
  `/wall` shows it on a projector. An XSS in the wall view during your own
  workshop would be a memorable way to end the session. Render as text, never
  `innerHTML`.
- Cap body size at ~256KB; reject larger with 413.
- Rate limit per code (say 10/min) and per source IP.
- Codes are write-only targets: knowing a code lets you post to it and read it.
  That is acceptable here — nothing sensitive should go through it. Say so in
  the step-05 narration, because someone will ask.
- Cap total codes (a few hundred) so a loop cannot exhaust the disk.
- Cap deliveries per code so a runaway CronJob over a month can't fill the PVC.
- Everything goes away with the hub on 2026-10-22.

## It lives for a month

The sink isn't just a workshop prop — it's the only feedback loop attendees
have that their agent is still working. Someone glancing at their page a
fortnight later and seeing fourteen daily reports stacked up is a better
advert for kagent than anything that happens in the room.

Two things follow from that: the log generators on the hub have to keep
running (an empty report every day is worse than no report), and the page
should show a timestamp per delivery so a stale one is obvious at a glance.

Be straight with people about what browser-only history means, in one line on
the page: it's **this browser on this device**. Clear site data, switch to
their laptop from their phone, and the archive starts over — the server buffer
backfills the last thirty, but anything older is gone. That's a fair trade for
not running a database, and it only bites people who were already curious
enough to come back, but it shouldn't be a surprise.

## Why not Slack

Slack needs a workspace, an app, an incoming-webhook URL per person, and admin
approval that some attendees' corporate Slack will refuse. That is a
ten-minute detour in a sixty-minute session. The sink costs you one small
service on a cluster you are already running.
