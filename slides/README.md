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

## Hosted on the hub

```bash
make hub-10        # from the repo root
```

builds the deck on the hub and serves it over HTTPS; `make status` prints the
address. It needs no Node or Docker on your machine: the build runs in a
container on the cluster. Run it again after any change to `slides/`,
including after `make record`. The join QR code always points at the hub the
deck was built on.

Keys: arrows or space to move, `f` for fullscreen, type a number to jump to
that slide. Swipe or tap on a phone.

## Before each event

- **`src/event.js`** — the event name and place, shown on the title slide and
  in the corner of every other one.
- **The join QR code** is generated at build time from, in order: `CTF_URL` in
  the environment, `.state/ctf-endpoint` (written by `make hub-09`), or a
  placeholder. Build the deck *after* the hub has its address, and check the
  code on the join slide with a phone.

```bash
CTF_URL=https://ctf.example.org npm run build
```

## The recordings

Nine slides are full-screen terminal recordings of the build: a cluster being
created with Terraform, the kagent install, one slide per section of each,
then each of the three agents. The room plays on a hub that already exists;
the recordings are how the deck shows it being built anyway.

```bash
make record          # from the repo root; needs asciinema and agg
make record N=0      # just the cluster; needs terraform
make record N=1      # just the install
make hub-10          # rebuild the hosted deck with them
```

They are written to `src/assets/` and picked up by name: `demo-kagent-0-1.gif`
onwards for the cluster, `-1-1.gif` onwards for the install, `demo-kagent-2.gif`
to `-4.gif` for the agents. A recording that does not exist yet shows a note
on its slide rather than breaking the build. The cluster and the install are
cut wherever their step clears the screen; if `make record` reports a
different number of parts, change the `DemoCluster` or `DemoInstall` list in
`src/slides/index.jsx` to match.

The cluster recording is a real `terraform apply` of `terraform/main.tf`. It
creates a second three-node cluster next to the hub for a few minutes and
destroys it when the recording ends.

The step banners and the guard in front of kagent are left out of the
recordings. The guard is still installed and tested while recording.

Recording uninstalls kagent and deletes the agents, then installs and creates
them again, so that the terminal shows a build from nothing. That wipes
kagent's chat history. Do it before the event.

The GIFs are sized for the 1920×1080 stage and have a black background, so they
fill the slide with no visible edge. The logo, slide counter, join code and
progress bar are hidden while one is up.

## The Grafana screenshots

Three slides before the join code show what Grafana Explore looks like, where
the query goes and how to set the time range. The screenshots are of this hub:

```bash
scripts/grafana-shots.sh     # from the repo root; then make hub-10
```

It runs a headless browser in a pod on the hub, so needs nothing installed. It
prints where the query box and the time picker are; if a Grafana upgrade moves
them, copy the numbers into `src/slides/GrafanaSlides.jsx`.

## Where the deck sits in the session

The deck stays on the projector throughout. Two of its slides are the live
scoreboard (the CTF app's `/board`, framed): one after the join code, which
stays up through round one, and one for round two. `docs/RUNSHEET.md` has the timings.

## The old deck

`archive/` is the September 2026 PowerPoint deck and its generator, for the
build-your-own-cluster format. Nothing uses it.
