# The slide deck

A React deck on a fixed 1920×1080 stage, built with Vite — the same setup as
the KCD Indonesia 2026 deck. One component per slide in `src/slides/`; the
order is `src/slides/index.jsx`.

```bash
cd slides
npm ci
npm run dev        # http://localhost:5173, live reload
npm run build      # static site in dist/
```

Keys: arrows or space to move, `f` for fullscreen, type a number to jump to
that slide. Swipe or tap on a phone.

## Before each event

- **`src/event.js`** — the event name and place, shown on the title slide and
  in the corner of every other one.
- **The join QR code** is generated at build time from, in order: `CTF_URL` in
  the environment, `.state/ctf-endpoint` (written by `make hub-09`), or a
  placeholder. Build the deck *after* the hub has its address, and check the
  code on slide 4 with a phone.

```bash
CTF_URL=https://ctf.example.org npm run build
```

## Where the deck sits in the session

The projector is on the scoreboard (`/board`), not this deck, while a round is
running. `index.jsx` marks the slides you leave from and come back to, and
`docs/RUNSHEET.md` has the timings.

## The old deck

`archive/` is the September 2026 PowerPoint deck and its generator, for the
build-your-own-cluster format. Nothing uses it.
