#!/bin/bash
set -euo pipefail

CLOUD="${1:-}"
COMMAND="${2:-}"

if [[ -z "$CLOUD" || -z "$COMMAND" ]]; then
  echo "Usage: ./deploy.sh <gcp|aws|azure> <init|plan|apply|destroy|output|show>"
  exit 1
fi

if [[ "$CLOUD" != "gcp" && "$CLOUD" != "aws" && "$CLOUD" != "azure" ]]; then
  echo "Error: cloud must be 'gcp', 'aws', or 'azure'"
  exit 1
fi

cd infrastructure/environments/learning

cp "backends/backend-${CLOUD}.tf.template" backend.tf

case "$COMMAND" in
  init)
    terraform init -reconfigure -backend-config="backends/${CLOUD}.hcl"
    ;;
  plan|apply|destroy)
    terraform "$COMMAND" -var="cloud=${CLOUD}"
    ;;
  output|show)
    terraform "$COMMAND"
    ;;
  *)
    terraform "$COMMAND"
    ;;
esac