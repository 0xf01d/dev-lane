#!/usr/bin/env python3
"""Emit opencode.json from env vars. Called by lane-entrypoint unless the
operator supplied OPENCODE_CONFIG / OPENCODE_CONFIG_CONTENT themselves.

Two optional custom providers:
  AISIX_BASE_URL + AISIX_API_KEY (+ AISIX_MODEL, default "auto")
      -> provider "aisix" via @ai-sdk/anthropic. AISIX_BASE_URL is the
         Anthropic-compatible root; "/v1" is appended unless already present
         because @ai-sdk/anthropic appends /messages to <baseURL>/v1.
  OPENAI_COMPAT_BASE_URL + OPENAI_COMPAT_API_KEY + OPENAI_COMPAT_MODEL
      -> provider "custom-openai" via @ai-sdk/openai-compatible. The base URL
         is used as-is (@ai-sdk/openai-compatible appends /chat/completions).

Auth for the OpenCode free tier needs no config: opencode picks up
OPENCODE_API_KEY from the environment on its own.
"""
import json
import os

schema = "https://opencode.ai/config.json"
providers = {}

aisix_base = os.environ.get("AISIX_BASE_URL", "").strip()
aisix_key = os.environ.get("AISIX_API_KEY", "").strip()
aisix_model = os.environ.get("AISIX_MODEL", "").strip() or "auto"
if aisix_base and aisix_key:
    base = aisix_base.rstrip("/")
    if not base.endswith("/v1"):
        base += "/v1"
    providers["aisix"] = {
        "npm": "@ai-sdk/anthropic",
        "name": "aisix (Anthropic-compatible)",
        "options": {"baseURL": base, "apiKey": aisix_key},
        "models": {aisix_model: {"name": aisix_model}},
    }

oc_base = os.environ.get("OPENAI_COMPAT_BASE_URL", "").strip()
oc_key = os.environ.get("OPENAI_COMPAT_API_KEY", "").strip()
oc_model = os.environ.get("OPENAI_COMPAT_MODEL", "").strip()
if oc_base and oc_key and oc_model:
    providers["custom-openai"] = {
        "npm": "@ai-sdk/openai-compatible",
        "name": os.environ.get("OPENAI_COMPAT_NAME", "").strip() or "custom OpenAI-compatible",
        "options": {"baseURL": oc_base.rstrip("/"), "apiKey": oc_key},
        "models": {oc_model: {"name": oc_model}},
    }

cfg = {
    "$schema": schema,
    "autoupdate": False,
    "model": os.environ.get("OC_MODEL", "").strip() or "opencode/step-5-preview-free",
}
if providers:
    cfg["provider"] = providers

print(json.dumps(cfg, indent=2))
