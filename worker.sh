#!/usr/bin/env bash
# ${WORKER_NAME}-worker: Git-native worker. Instantiate from worker-template.
#
# The loop:
#   git pull → check inbox/ → claim task → call MiniMax → write outbox/ → commit → push → sleep
#
# State is in Git. The machine is disposable. Kill it, clone elsewhere, continue.
#
# Usage:
#   ./worker.sh [repo-dir] [--once]
#   WORKER_REPO defaults to ~/minimax-worker
#   POLL_INTERVAL defaults to 60 seconds
#
# The MiniMax credential comes from the vault via the skill's chat.py.
# It is NEVER in this repo. If chat.py can't authenticate, the worker
# logs the error and leaves the task unclaimed.

set -u

WORKER_NAME="zai"  # <-- CHANGE: minimax, zai, kimi, ...
REPO_DIR="${1:-$HOME/${WORKER_NAME}-worker}"
POLL_INTERVAL="${POLL_INTERVAL:-60}"
CHAT_PY="${CHAT_PY:-$HOME/workspace/skills/zai/bin/chat.py}"  # <-- CHANGE: point at your model CLI
ONCE="${2:-}"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$REPO_DIR/log/worker.log"
}

die() { log "FATAL: $*"; exit 1; }

[ -d "$REPO_DIR/.git" ] || die "not a git repo: $REPO_DIR"
[ -x "$CHAT_PY" ] || [ -f "$CHAT_PY" ] || die "chat.py not found: $CHAT_PY"

cd "$REPO_DIR" || die "cannot cd $REPO_DIR"

process_one() {
  # Pull first — never work on stale state.
  git pull --quiet --rebase 2>/dev/null || log "WARN: pull failed, working with local state"

  # Find the oldest unclaimed task.
  task="$(ls inbox/*.json 2>/dev/null | head -1)"
  [ -z "$task" ] && return 1  # nothing to do

  task_id="$(basename "$task" .json)"
  log "Claiming task: $task_id"

  # Claim it: move to claimed/ so no other worker takes it.
  claimed="claimed/${task_id}.json"
  mv "$task" "$claimed" || { log "WARN: lost race on $task_id"; return 1; }
  git add -A && git commit -qm "claim $task_id" && git push --quiet 2>/dev/null \
    || log "WARN: push after claim failed (will retry)"

  # Read the task.
  prompt="$(python3 -c "import json;print(json.load(open('$claimed'))['prompt'])")"
  system="$(python3 -c "import json;print(json.load(open('$claimed')).get('system',''))")"
  model="$(python3 -c "import json;print(json.load(open('$claimed')).get('model',''))")"
  max_tokens="$(python3 -c "import json;print(json.load(open('$claimed')).get('max_tokens',4000))")"

  log "Calling MiniMax for $task_id (model=${model:-default})"

  # Call the model. Credential attaches via vault surrogate inside chat.py.
  args=("$prompt" "--max-tokens" "$max_tokens")
  [ -n "$system" ] && args+=(--system "$system")
  [ -n "$model" ] && args+=(--model "$model")

  export WORKER_NAME
  if result="$(python3 "$CHAT_PY" "${args[@]}" 2>"$REPO_DIR/log/${task_id}.err")"; then
    # Success: write result to outbox/.
    python3 - "$task_id" "$result" <<'EOF'
import json, sys, datetime
import os
task_id, result = sys.argv[1], sys.argv[2]
worker_name = os.environ.get("WORKER_NAME", "unknown")
out = {
  "task_id": task_id,
  "worker": worker_name,
  "completed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
  "result": result,
}
json.dump(out, open(f"outbox/{task_id}.json", "w"), indent=2)
EOF
    log "Done: $task_id"
  else
    # Failure: write error marker, move task back to inbox for retry.
    err="$(cat "$REPO_DIR/log/${task_id}.err" | head -5)"
    log "ERROR on $task_id: $err"
    mv "$claimed" "inbox/${task_id}.json"
    # Count retries; after 3, move to dead/.
    retries="$(python3 -c "
import json
d = json.load(open('inbox/${task_id}.json'))
d['retries'] = d.get('retries', 0) + 1
json.dump(d, open('inbox/${task_id}.json','w'), indent=2)
print(d['retries'])")"
    if [ "$retries" -ge 3 ]; then
      mv "inbox/${task_id}.json" "dead/${task_id}.json"
      log "Moved $task_id to dead/ after 3 retries"
    fi
  fi

  git add -A && git commit -qm "result $task_id" && git push --quiet 2>/dev/null \
    || log "WARN: push after result failed (will retry next loop)"
  return 0
}

log "${WORKER_NAME}-worker starting (repo=$REPO_DIR, interval=${POLL_INTERVAL}s)"

while true; do
  process_one || true
  [ "$ONCE" = "--once" ] && { log "once mode, exiting"; exit 0; }
  sleep "$POLL_INTERVAL"
done
