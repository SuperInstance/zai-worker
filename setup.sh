#!/usr/bin/env bash
# setup.sh — prepare any machine to run the zai-worker.
# Checks dependencies, no system-wide installs. Everything stays in ~.
set -u

ok=1
need() { command -v "$1" >/dev/null 2>&1 || { echo "MISSING: $1"; ok=0; }; }

echo "== zai-worker setup =="
need git
need python3

CHAT="$HOME/workspace/skills/zai/bin/chat.py"
if [ -f "$CHAT" ]; then
  echo "OK: chat.py found"
else
  echo "WARN: chat.py not at $CHAT"
  echo "  This worker needs the zai skill (vault credential broker)."
  echo "  On Muse-managed machines it's at ~/workspace/skills/zai/."
  ok=0
fi

# Quick credential check: does chat.py attach a surrogate without 401?
echo "Testing model call (short prompt)..."
if python3 "$CHAT" "Reply with the single word: alive" --max-tokens 10 2>/dev/null | grep -qi alive; then
  echo "OK: zai API reachable via vault"
else
  echo "WARN: model call failed — check vault credential (custom.zai)"
  ok=0
fi

if [ "$ok" = "1" ]; then
  echo "READY: run ./worker.sh"
else
  echo "NOT READY: fix the WARN lines above"
  exit 1
fi
