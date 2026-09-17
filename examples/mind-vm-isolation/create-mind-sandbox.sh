#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Create or start one OpenShell VM sandbox per user MIND.
# Reuses an existing sandbox. Refuses provider credentials.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_FILE="${SCRIPT_DIR}/policy.yaml"
NAME="${MIND_SANDBOX_NAME:-mind-${USER:-user}}"
CPU="${MIND_CPU:-2}"
MEMORY="${MIND_MEMORY:-4Gi}"
NATS_URL="${MIND_NATS_URL:-nats://host.openshell.internal:4222}"
SWITCH_URL="${MIND_SWITCH_URL:-http://host.openshell.internal:8789/v1}"
DB_PATH="${MIND_DB_PATH:-/sandbox/nooa.sqlite3}"

refuse() {
  echo "create-mind-sandbox: $*" >&2
  exit 2
}

command -v openshell >/dev/null 2>&1 || refuse "openshell CLI not on PATH"

if [[ -z "${MIND_IMAGE:-}" ]]; then
  refuse "MIND_IMAGE is required (distroless Magentic MIND image)"
fi

if [[ ! -f "$POLICY_FILE" ]]; then
  refuse "missing policy file: $POLICY_FILE"
fi

for key in \
  MIND_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY \
  AWS_SECRET_ACCESS_KEY GOOGLE_API_KEY AZURE_OPENAI_API_KEY
do
  if [[ -n "${!key:-}" ]]; then
    refuse "refusing to launch MIND while $key is set; vault and SWITCH hold credentials"
  fi
done

if [[ "$DB_PATH" == /mind-data/* ]]; then
  refuse "DB_PATH=$DB_PATH is not in the Landlock allowlist; use /sandbox/..."
fi

if openshell sandbox get "$NAME" >/dev/null 2>&1; then
  echo "starting existing MIND sandbox $NAME"
  if ! openshell sandbox start "$NAME"; then
    echo "sandbox $NAME is already running" >&2
  fi
  exit 0
fi

echo "creating MIND sandbox $NAME (cpu=$CPU memory=$MEMORY)"
exec openshell sandbox create \
  --name "$NAME" \
  --from "$MIND_IMAGE" \
  --cpu "$CPU" \
  --memory "$MEMORY" \
  --policy "$POLICY_FILE" \
  --detach \
  --env "MM_NATS_URL=$NATS_URL" \
  --env "SWITCH_URL=$SWITCH_URL" \
  --env "DB_PATH=$DB_PATH" \
  -- harness.py
