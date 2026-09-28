# The slide deck

`build.py` holds the deck's content — one `slide(...)` call each, with the
speaker notes that make up the run of show. `mkpptx.py` turns that into a
`.pptx` with no third-party libraries, because the machine this was written on
had no way to install one.

```bash
python3 slides/build.py
```

Writes both outputs next to this file:

- `Your Cluster Called - kagent workshop.pptx` — drag into Google Drive and
  open with Slides; it converts on the way in
- `your-cluster-called-deck.md` — the same content as markdown, for pasting
  into a design tool

Editing the deck means editing `build.py` and re-running it. The two outputs
come from one source, so they cannot drift.

Four values in here are specific to the September 2026 run and need changing
before the deck is used again: the join URL and passphrase (slides 1 and 4),
the Grafana URL (slide 2), and the repo URL (last slide).
