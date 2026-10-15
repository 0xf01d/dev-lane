#!/usr/bin/env bash
# Verifies passing criterion 5: a custom (Anthropic-compatible "aisix",
# or generic OpenAI-compatible) provider is injectable purely via env vars.
# Run against a container started with AISIX_* env vars set.
# If AISIX_API_KEY is a real key, also drives one live message through it.
set -euo pipefail

BASE="${SMOKE_BASE_URL:-http://127.0.0.1:4096}"
AISIX_MODEL="${AISIX_MODEL:-auto}"

say() { printf '\n=== %s ===\n' "$*"; }
die() { echo "INJECT FAIL: $*" >&2; exit 1; }

say "provider injected via env"
curl -sf "$BASE/config/providers" | python3 - "$AISIX_MODEL" <<'PY'
import json, sys
expected_model = sys.argv[1]
d = json.load(sys.stdin)
ids = [p["id"] for p in d["providers"]]
assert "aisix" in ids, f"aisix provider not injected; got {ids}"
prov = [p for p in d["providers"] if p["id"] == "aisix"][0]
models = list(prov.get("models", {}).keys())
assert expected_model in models, f"model {expected_model} missing; got {models}"
print("aisix provider OK — model:", expected_model, "| baseURL:", prov["options"]["baseURL"])
PY

say "default model switched to aisix/${AISIX_MODEL}"
curl -sf "$BASE/config" | grep -q "\"model\":\"aisix/${AISIX_MODEL}\"" \
  || die "default model is not aisix/${AISIX_MODEL}"

if [ -n "${AISIX_API_KEY:-}" ] && [ "${AISIX_LIVE_TEST:-1}" = "1" ]; then
  say "live message through aisix provider"
  SID="$(curl -sf -X POST "$BASE/session" -H 'content-type: application/json' -d '{}' \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
  R="$(curl -sf --max-time 240 -X POST "$BASE/session/$SID/message" \
    -H 'content-type: application/json' \
    -d '{"parts":[{"type":"text","text":"Reply with exactly: AISIX-OK"}]}')"
  T="$(printf '%s' "$R" | python3 -c 'import json,sys
d = json.load(sys.stdin)
print(" ".join(p.get("text", "") for p in d.get("parts", []) if p.get("type") == "text"))')"
  echo "reply: $T"
  echo "$T" | grep -q 'AISIX-OK' || die "aisix live message failed (got: $T)"
else
  say "AISIX_API_KEY not set — skipping live call (config injection verified)"
fi

printf '\nPROVIDER INJECTION PASSED\n'
