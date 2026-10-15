#!/usr/bin/env bash
# dev-lane entrypoint: seed /nix if a fresh volume was mounted there,
# wire up env-driven opencode config, then exec the requested command in /work.
set -euo pipefail

# --- /nix persistence -------------------------------------------------------
# The image ships a complete single-user nix install. If a volume is mounted
# over /nix it starts empty; seed it once from the in-image snapshot so the
# store (and anything installed into it later) lives on the volume.
if [ ! -d /nix/store ] || [ -z "$(ls -A /nix/store 2>/dev/null)" ]; then
  echo "[lane-entrypoint] empty /nix detected — seeding from image snapshot (one-time, ~1min)..."
  mkdir -p /nix
  cp -a /nix-seed/. /nix/
fi

# Make the nix profile reachable in non-login, non-interactive shells.
for p in /home/lane/.nix-profile/bin /nix/var/nix/profiles/profile/bin /nix/var/nix/profiles/default/bin; do
  case ":$PATH:" in
    *":$p:"*) ;;
    *) [ -d "$p" ] && export PATH="$p:$PATH" ;;
  esac
done
if [ -f "${HOME}/.nix-profile/etc/profile.d/nix.sh" ]; then
  # shellcheck disable=SC1091
  . "${HOME}/.nix-profile/etc/profile.d/nix.sh"
fi

# --- optional lane state persistence (opencode session DB) -------------------
if [ -n "${LANE_STATE_DIR:-}" ]; then
  target="${LANE_STATE_DIR%/}/opencode"
  mkdir -p "$target"
  if [ "$(readlink "${HOME}/.local/share/opencode" 2>/dev/null)" != "$target" ]; then
    mkdir -p "$(dirname "${HOME}/.local/share/opencode")"
    rm -rf "${HOME}/.local/share/opencode"
    ln -s "$target" "${HOME}/.local/share/opencode"
  fi
fi

# --- model / provider selection ---------------------------------------------
# Precedence: explicit OC_MODEL > aisix (Anthropic-compatible) > generic
# OpenAI-compatible > OpenCode free tier default.
if [ -z "${OC_MODEL:-}" ]; then
  if [ -n "${AISIX_BASE_URL:-}" ] && [ -n "${AISIX_API_KEY:-}" ]; then
    export OC_MODEL="aisix/${AISIX_MODEL:-auto}"
  elif [ -n "${OPENAI_COMPAT_BASE_URL:-}" ] && [ -n "${OPENAI_COMPAT_API_KEY:-}" ] && [ -n "${OPENAI_COMPAT_MODEL:-}" ]; then
    export OC_MODEL="custom-openai/${OPENAI_COMPAT_MODEL}"
  else
    export OC_MODEL="opencode/step-5-preview-free"
  fi
fi

# Generate the global opencode config from env vars unless the operator
# supplied their own (OPENCODE_CONFIG / OPENCODE_CONFIG_CONTENT always win —
# both have higher precedence than the global config file in opencode).
if [ -z "${OPENCODE_CONFIG:-}" ] && [ -z "${OPENCODE_CONFIG_CONTENT:-}" ]; then
  config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/opencode"
  mkdir -p "$config_dir"
  python3 /opt/lane/gen-config.py > "${config_dir}/opencode.json"
fi

cd "${LANE_WORKDIR:-/work}"
if [ "$#" -eq 0 ]; then
  set -- bash
fi
exec "$@"
