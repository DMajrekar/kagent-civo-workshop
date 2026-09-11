#!/usr/bin/env bash
# title: Check your laptop is ready (do this before the day)
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

banner "Step 00 — before you arrive"

say "This is the only thing you need to do in advance, and it takes about ten"
say "minutes. Everything else happens in the session."
say ""
say "There is no time to debug laptop setups during a sixty-minute workshop, so"
say "if this does not pass, get in touch beforehand rather than on the day."
printf '\n'

exec "$REPO_ROOT/scripts/doctor.sh"
