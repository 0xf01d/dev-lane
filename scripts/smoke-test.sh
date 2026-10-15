#!/usr/bin/env bash
# Serve-based smoke test: drives a coding lane through `opencode serve`
# running INSIDE the dev-lane container (host: port-mapped; in-cluster:
# exec/pod-IP — see README). Implements the project passing criteria:
#   1. serve is up (health)
#   2. POST /session + POST /session/{id}/message with a trivial prompt
#   3. completion comes back with reply text
#   4. SECOND message on the same session sees prior context (persistence)
#   5. model config injectable via env (covered by provider-inject-test.sh)
#
# Env: SMOKE_BASE_URL (default http://127.0.0.1:4096), OPENCODE_API_KEY.
set -euo pipefail

BASE="${SMOKE_BASE_URL:-http://127.0.0.1:4096}"
SECRET="BANANA-8128"
: "${OPENCODE_API_KEY:?OPENCODE_API_KEY must be set in the environment}"

say() { printf '\n=== %s ===\n' "$*"; }
die() { echo "SMOKE FAIL: $*" >&2; exit 1; }

reply_text() {
  python3 -c 'import json,sys
d = json.load(sys.stdin)
print(" ".join(p.get("text", "") for p in d.get("parts", []) if p.get("type") == "text"))'
}

say "1. health ($BASE)"
curl -sf "$BASE/global/health" | grep -q '"healthy":true' || die "health endpoint not healthy"
curl -sf "$BASE/global/health" | grep -o '"version":"[^"]*"'

say "default model"
curl -sf "$BASE/config" | grep -o '"model":"[^"]*"' | head -1

say "2. create session"
SID="$(curl -sf -X POST "$BASE/session" \
  -H 'content-type: application/json' \
  -d '{"title":"dev-lane smoke"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
[ -n "$SID" ] || die "could not create session"
echo "session: $SID"

send() {
  curl -sf --max-time 240 -X POST "$BASE/session/$SID/message" \
    -H 'content-type: application/json' -d "$1"
}

say "3. message 1 — trivial prompt, completion with reply text"
R1="$(send '{"parts":[{"type":"text","text":"Memorize this secret code: '"$SECRET"'. Reply with exactly: ACK"}]}')"
T1="$(printf '%s' "$R1" | reply_text)"
echo "reply 1: $T1"
[ -n "$T1" ] || die "empty completion"
echo "$T1" | grep -q 'ACK' || die "did not get ACK (got: $T1)"

say "4. message 2 — same session must see prior context"
R2="$(send '{"parts":[{"type":"text","text":"What is the secret code I gave you? Reply with just the code."}]}')"
T2="$(printf '%s' "$R2" | reply_text)"
echo "reply 2: $T2"
echo "$T2" | grep -q "$SECRET" || die "second message lost context (got: $T2)"

say "4b. messages persisted server-side in the session"
N="$(curl -sf "$BASE/session/$SID/message" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
echo "$N messages in session $SID"
[ "$N" -ge 4 ] || die "expected >=4 persisted messages, got $N"

printf '\nSMOKE PASSED (serve-driven lane, multi-turn persistence OK)\n'
