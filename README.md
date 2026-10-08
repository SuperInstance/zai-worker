# Worker Template

Copy this directory to make a worker for any model API. Three files to change.

## How to instantiate

```bash
cp -r worker-template zai-worker
cd zai-worker
# 1. Edit worker.sh: set CHAT_PY, WORKER_NAME, API-specific args
# 2. Edit README.md: rename, update task/result examples
# 3. Edit setup.sh: point at the right skill + credential name
```

That's it. The inbox/claimed/outbox/dead/log shape stays identical across all workers.

## What differs per worker

| Piece | MiniMax | ZAI | Kimi |
|-------|---------|-----|------|
| `CHAT_PY` | `skills/minimax/bin/chat.py` | `skills/zai/bin/chat.py` | (no direct CLI — see note) |
| `WORKER_NAME` | `minimax` | `zai` | `kimi` |
| Credential | `custom.minimax` | `custom.zai` | via cloud box |
| Default model | `MiniMax-Text-01` | `glm-4.5` | — |

## Kimi note

There is no direct Kimi model CLI on this machine — Kimi is reached through its cloud box (the Prospector/Claw). A kimi-worker has two options:

1. **SSH worker**: the poll loop runs on a machine that can `ssh kimi-box` and run the model call there. The `CHAT_PY` becomes a wrapper script that forwards the prompt over SSH.
2. **Future**: when a Kimi API CLI exists, drop it in like the others.

The template's `worker.sh` has a `call_model()` function — override just that function for the SSH-forwarding variant. Everything else (claim, commit, push, retry) stays the same.

## The contract (do not change)

Every worker, regardless of model, MUST:

1. Use the same repo shape: `inbox/ claimed/ outbox/ dead/ log/`
2. Use the same task format: `{"prompt": ..., "system": ..., "model": ..., "max_tokens": ..., "from": ...}`
3. Use the same result format: `{"task_id": ..., "worker": "<name>", "completed_at": ..., "result": ...}`
4. Never put credentials in Git. Ever.
5. Claim before working (move inbox → claimed, commit, push).
6. Retry 3x, then dead/.

A zero agent doesn't care which worker picks up the task. The contract is the interface.
