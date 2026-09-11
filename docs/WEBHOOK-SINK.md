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

- `POST /hook/:code` — accept any content type, store, return 204
- `GET /c/:code` — HTML page, live via SSE (poll fallback for hostile WiFi)
- `GET /api/c/:code` — JSON, for the curious
- `GET /wall` — all codes
- `POST /api/code` — mint a new code

Storage: in-memory ring buffer, last 20 deliveries per code, 48h TTL. SQLite on
a PVC only if you want codes to survive a restart — for a 60-minute workshop,
in-memory plus a `replicas: 1` Deployment is honestly fine, and one less thing
to break.

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
- Cap total codes (a few hundred) so a loop cannot exhaust memory.
- Expire everything 48h after the event.

## Why not Slack

Slack needs a workspace, an app, an incoming-webhook URL per person, and admin
approval that some attendees' corporate Slack will refuse. That is a
ten-minute detour in a sixty-minute session. The sink costs you one small
service on a cluster you are already running.
