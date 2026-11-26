#!/usr/bin/env python3
"""Split an asciinema recording into one file per screen.

  split-cast.py in.cast out-prefix      writes out-prefix-1.cast, -2.cast, ...

A step clears the screen between its sections when it is being recorded
(DEMO_CLEAR_SECTIONS). Cutting there gives one recording per section, so each
can sit on its own slide and the presenter moves on when they are ready rather
than when the recording does. Prints the number of parts written.
"""
import json, re, sys

CLEAR = re.compile(r"\x1b\[H\x1b\[[23]J(?:\x1b\[3J)?")
VISIBLE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\s")

src, prefix = sys.argv[1], sys.argv[2]
lines = open(src, encoding="utf-8").read().splitlines()
header = json.loads(lines[0])
header.pop("timestamp", None)

parts, cur = [], []
for line in lines[1:]:
    t, kind, data = json.loads(line)
    if kind != "o":
        continue
    chunks = CLEAR.split(data)
    for i, chunk in enumerate(chunks):
        if i:                      # a clear sat before this chunk
            parts.append(cur); cur = []
        if chunk:
            cur.append((t, chunk))
parts.append(cur)

# A part with nothing printable in it is the gap between two clears.
parts = [p for p in parts if VISIBLE.sub("", "".join(c for _, c in p))]

for n, part in enumerate(parts, 1):
    t0 = part[0][0]
    with open(f"{prefix}-{n}.cast", "w", encoding="utf-8") as f:
        f.write(json.dumps(header) + "\n")
        for t, chunk in part:
            f.write(json.dumps([round(t - t0, 6), "o", chunk]) + "\n")
print(len(parts))
