# dev-lane

**One coding lane as a container image.** `ghcr.io/0xf01d/dev-lane`

The image ships [OpenCode CLI](https://opencode.ai) (`opencode run` and
`opencode serve` both work), [Nix](https://nixos.org) with channels pinned to
**nixpkgs-unstable** as an escape hatch for anything not preinstalled, and a
full polyglot toolchain. Built by GitHub Actions for `linux/amd64` +
`linux/arm64`; CI drives a live lane through `opencode serve` on every push.

- **Base image:** `debian:stable-slim` (currently Debian 13 "trixie").
  **Why:** slim base, and trixie's apt toolchains are current (Python 3.13,
  Go 1.24, recent rustc/erlang/elixir) — ubuntu:24.04 would add size and
  ship *older* compilers than Debian stable does today. Anything newer than
  the apt snapshot is one `nix run nixpkgs#<pkg>` away.
- **Auth:** never baked in. `OPENCODE_API_KEY` is passed via env at runtime.
- **Default model:** `opencode/step-5-preview-free` (OpenCode free tier).
  As of 2026-10-15 this is the best free model that is not rate-limited
  (deepseek-v4.1-flash-free and muse-spark are returning 429).

## Contents

| Layer | What |
| --- | --- |
| Base | `debian:stable-slim`, `build-essential`, `git`, `jq`, `curl`, `tmux`, `openssh-client`, `ca-certificates` |
| Node | Node 24 LTS + npm (copied from the official multi-arch `node:24-bookworm-slim`) |
| OpenCode | `opencode-ai` (npm global) — `opencode` binary works offline after build |
| Nix | Single-user install (owned by `lane`), channel `nixpkgs-unstable`, flake registry → `github:NixOS/nixpkgs/nixpkgs-unstable` |
| Languages | Rust (rustc+cargo), Elixir + Erlang/OTP, Python 3 + pip + venv, Go, Node 24 LTS |
| User | `lane` (uid 1000), home `/home/lane`, workdir `/work` |

## Quickstart

```bash
docker pull ghcr.io/0xf01d/dev-lane:latest

# Interactive lane (bash in /work)
docker run --rm -it \
  -e OPENCODE_API_KEY="$OPENCODE_API_KEY" \
  -v dev-work:/work -v dev-nix:/nix \
  ghcr.io/0xf01d/dev-lane

# Driven lane: run the agent one-shot
docker run --rm -e OPENCODE_API_KEY="$OPENCODE_API_KEY" \
  ghcr.io/0xf01d/dev-lane opencode run -m opencode/step-5-preview-free "hello"

# Driven lane: headless HTTP server you can drive from outside the container
docker run -d --name lane1 -p 4096:4096 \
  -e OPENCODE_API_KEY="$OPENCODE_API_KEY" \
  ghcr.io/0xf01d/dev-lane opencode serve --hostname 0.0.0.0 --port 4096

curl -s -X POST localhost:4096/session -H 'content-type: application/json' -d '{"title":"lane1"}'
# -> {"id":"ses_..."}  then POST /session/{id}/message {"parts":[{"type":"text","text":"..."}]}
```

### Server API (drive a lane from anywhere)

`opencode serve` exposes an HTTP API ([spec](https://opencode.ai/docs/server/),
OpenAPI at `/doc`):

1. `POST /session` — create a lane session → `{"id":"ses_..."}`
2. `POST /session/{id}/message` with
   `{"parts":[{"type":"text","text":"prompt"}]}` — synchronous; the response
   contains the assistant reply (`{info, parts}`). For streaming instead use
   `POST /session/{id}/prompt_async` (204) + SSE `GET /event`.
3. Every later message on the same session sees the full prior context —
   sessions live in `~/.local/share/opencode/opencode.db` (SQLite).
4. Optionally protect the server with `OPENCODE_SERVER_PASSWORD` (HTTP basic
   auth, user defaults to `opencode`).

## Volumes

| Mount | Purpose | Notes |
| --- | --- | --- |
| `/work` | lane workspace (code, repos) | create dirs as `lane` (uid 1000) or set `user: "1000:1000"` / `fsGroup: 1000` |
| `/nix` | nix store — **persistence for the escape hatch** | starts empty on a fresh volume; the entrypoint seeds it once from the in-image snapshot (~1 min), after which everything you `nix`-install persists across restarts |
| `$LANE_STATE_DIR` | optional: lane state | set `LANE_STATE_DIR=/work/.lane-state` to keep opencode session DBs on the `/work` volume so conversations survive container replacement |

## Environment variables

| Var | Default | Meaning |
| --- | --- | --- |
| `OPENCODE_API_KEY` | — | OpenCode auth (free tier / Zen). Read by opencode from env; never written to disk. **Required for model calls.** |
| `OC_MODEL` | `opencode/step-5-preview-free` | default `provider/model` for the lane |
| `AISIX_BASE_URL` | — | Anthropic-compatible endpoint root (e.g. your aisix/auto gateway). `/v1` is appended automatically unless present. Needs `AISIX_API_KEY`. |
| `AISIX_API_KEY` | — | key for the aisix provider |
| `AISIX_MODEL` | `auto` | model id on the aisix provider (`aisix/auto` = org default) |
| `OPENAI_COMPAT_BASE_URL` / `_API_KEY` / `_MODEL` / `_NAME` | — | generic OpenAI-compatible provider (`custom-openai/…`); base URL used as-is (SDK appends `/chat/completions`) |
| `OPENCODE_CONFIG` | — | path to your own opencode config file (overrides the generated global config) |
| `OPENCODE_CONFIG_CONTENT` | — | inline JSON config — highest precedence; disables entrypoint config generation entirely |
| `OPENCODE_SERVER_PASSWORD` | — | protects `opencode serve` with HTTP basic auth |
| `LANE_STATE_DIR` | — | dir for persistent lane state (symlinked into `~/.local/share`) |
| `LANE_WORKDIR` | `/work` | directory the entrypoint `cd`s into |

When `AISIX_*` (or `OPENAI_COMPAT_*`) is set and `OC_MODEL` is not, the lane
defaults to that provider's model automatically.

### Wiring aisix/auto (Anthropic-compatible)

```bash
docker run -d --name lane-aisix -p 4096:4096 \
  -e AISIX_BASE_URL="https://<aisix-host>/<anthropic-root>" \
  -e AISIX_API_KEY="..." \
  -e AISIX_MODEL=auto \
  ghcr.io/0xf01d/dev-lane opencode serve --hostname 0.0.0.0 --port 4096
```

Entrypoint generates `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": false,
  "model": "aisix/auto",
  "provider": {
    "aisix": {
      "npm": "@ai-sdk/anthropic",
      "name": "aisix (Anthropic-compatible)",
      "options": { "baseURL": "https://<aisix-host>/<anthropic-root>/v1", "apiKey": "..." },
      "models": { "auto": { "name": "auto" } }
    }
  }
}
```

Note the `/v1`: opencode's `@ai-sdk/anthropic` requests `<baseURL>/messages`,
so the base must be the root that serves `<root>/v1/messages`
(`https://api.anthropic.com/v1` style). The entrypoint appends `/v1` if the
URL doesn't already end with it.

For full control (multiple providers, model lists), skip the generator and set
`OPENCODE_CONFIG_CONTENT='{...}'` directly — opencode applies it on top of
everything else. `{env:VAR}` substitution works inside it.

## Nix escape hatch

```bash
nix --version                       # nix (Nix) 2.31.x, single-user, store on /nix
nix-channel --list                  # nixpkgs https://nixos.org/channels/nixpkgs-unstable
nix run nixpkgs#ripgrep -- --version    # flakes path (registry -> nixpkgs-unstable)
nix shell nixpkgs#ffmpeg
nix-env -iA nixpkgs.ripgrep             # legacy path via the pinned channel
```

Everything installed lands in `/nix` — keep it on a volume to persist.

## CI

`.github/workflows/build.yml`:

- **build** — on push to `main`, weekly cron, and `workflow_dispatch`.
  Buildx + QEMU, `linux/amd64` + `linux/arm64`, pushed to
  `ghcr.io/0xf01d/dev-lane` tagged `latest`, `sha-<full-sha>`,
  `date-YYYYMMDD`. GHA layer cache (apt/node/npm/nix layers cached).
- **smoke** — pulls the pushed `sha-` image and enforces the passing
  criteria:
  1. `opencode serve` up inside the container (health endpoint)
  2. `POST /session` + `POST /session/{id}/message` with a trivial prompt
  3. completion returns reply text (`scripts/smoke-test.sh`)
  4. second message on the same session recalls a planted secret —
     persistence proven (`opencode run` one-shot is tested too, but the
     serve lane is the deliverable)
  5. custom provider injectable via env — a second container starts with
     `AISIX_*` set; config shows provider `aisix` + model switch; live
     message through it if `AISIX_API_KEY` secret is set
     (`scripts/provider-inject-test.sh`)
  plus `opencode --version`, `nix --version`, hello-world for C/Rust/Go/
  Elixir/Python/Node, and `nix run nixpkgs#hello`.

Required repo secrets: `OPENCODE_API_KEY` (free tier). Optional:
`AISIX_BASE_URL`, `AISIX_API_KEY`, `AISIX_MODEL` for the live aisix leg.

## Kubernetes (namespace `hermes-generated-content`)

One image, one pod per lane, PVCs for `/work` and `/nix`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: lane1-work
  namespace: hermes-generated-content
spec:
  accessModes: ["ReadWriteOnce"]
  resources: { requests: { storage: 20Gi } }
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: lane1-nix
  namespace: hermes-generated-content
spec:
  accessModes: ["ReadWriteOnce"]
  resources: { requests: { storage: 20Gi } }
---
apiVersion: v1
kind: Secret
metadata:
  name: lane1-env
  namespace: hermes-generated-content
stringData:
  OPENCODE_API_KEY: "..."
  # optional aisix/auto:
  # AISIX_BASE_URL: "https://<aisix-host>/<anthropic-root>"
  # AISIX_API_KEY: "..."
  # AISIX_MODEL: auto
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lane1
  namespace: hermes-generated-content
spec:
  replicas: 1
  selector: { matchLabels: { app: lane1 } }
  template:
    metadata: { labels: { app: lane1 } }
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000          # lets the PVCs be writable by uid 1000
      containers:
        - name: lane
          image: ghcr.io/0xf01d/dev-lane:latest
          args: ["opencode", "serve", "--hostname", "0.0.0.0", "--port", "4096"]
          envFrom:
            - secretRef: { name: lane1-env }
          ports: [{ containerPort: 4096 }]
          readinessProbe:
            httpGet: { path: /global/health, port: 4096 }
            initialDelaySeconds: 5
          volumeMounts:
            - { name: work, mountPath: /work }
            - { name: nix,  mountPath: /nix  }
      volumes:
        - name: work
          persistentVolumeClaim: { claimName: lane1-work }
        - name: nix
          persistentVolumeClaim: { claimName: lane1-nix }
```

Notes:

- First boot on a fresh `/nix` PVC seeds the store from the image
  (read-only traffic to cache.nixos.org not needed for the seed; the seed is
  in-image). Subsequent restarts skip the seed.
- `securityContext.fsGroup: 1000` is what makes dynamically provisioned PVCs
  group-writable for `lane`.
- Drive the lane with `kubectl -n hermes-generated-content exec deploy/lane1 --
  curl -s -X POST localhost:4096/session ...` or expose via a Service.
- Add `LANE_STATE_DIR=/work/.lane-state` to keep session history on the work
  volume.

## Building locally

```bash
docker buildx build --platform linux/amd64 -t dev-lane:local --load .
docker run --rm -it -e OPENCODE_API_KEY="$OPENCODE_API_KEY" dev-lane:local
```

Smoke scripts are baked into the image: `docker exec <ctr> bash /opt/lane/toolchain-check.sh`.

## Versioning

Tags on ghcr: `latest` (main), `sha-<commit>`, `date-YYYYMMDD`. The weekly
cron rebuild refreshes the nixpkgs-unstable snapshot, the opencode release,
and apt packages; the same commit always rebuilds deterministically apart
from those floating pins.
