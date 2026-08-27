#!/bin/bash
#
# Runs the probe through LaunchServices and prints what it wrote.
#
# This wrapper is not a convenience — it is the correction that makes the whole spike valid.
# Exec'ing Contents/MacOS/probe straight from a shell leaves the SHELL'S application as the
# responsible process for TCC, so every Apple Events consent decision is attributed to the
# terminal (measured: the grant landed on "claude", not on the probe, and no probe row ever
# appeared in System Settings → Privacy & Security → Automation).
#
# `open` hands the launch to LaunchServices, which makes the bundle its own responsible
# process. Only then does com.svvoff.terminator.probe own its own TCC rows.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$HERE/build/Probe.app"
OUT="$HERE/build/probe-output.txt"

if [[ ! -d "$APP" ]]; then
  echo "no bundle at $APP — run build-probe.sh first" >&2
  exit 1
fi

: > "$OUT"
open -n -W -a "$APP" --args "$@"
cat "$OUT"
