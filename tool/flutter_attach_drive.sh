#!/usr/bin/env bash
# Drive flutter attach: connect, hot reload, then exit.
# Usage: bash tool/flutter_attach_drive.sh <vm-uri> [commands...]
# Commands: r=hot reload, R=hot restart, q=quit
set -e
URI="$1"; shift
CMDS="${*:-r q}"   # default: reload then quit

# Write commands to a fifo after attach settles
FIFO=$(mktemp -t flutter_drive_XXXX)
rm -f "$FIFO"; mkfifo "$FIFO"

# Send commands after a delay so attach can connect
(
  sleep 8  # wait for attach + compiler warm-up
  for cmd in $CMDS; do
    echo "$cmd"
    sleep 2
  done
  echo "q"
) > "$FIFO" &
CMD_PID=$!

flutter attach --debug-uri "$URI" < "$FIFO" 2>&1
kill $CMD_PID 2>/dev/null || true
rm -f "$FIFO"
