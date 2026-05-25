#!/usr/bin/env bash
# =============================================================================
# bootstrap/k3s-bootstrap.sh
# =============================================================================
# One-time setup script that must run BEFORE `terraform apply`.
#
# What it does:
#   1. Enables the Secret Manager API
#   2. Creates the k3s-cluster-token secret shell (if not exists)
#   3. Generates a cryptographically secure token and stores it as the
#      first secret version
#   4. Verifies the token is readable
#
# After this script succeeds, run:
#   terraform -chdir=terraform/k3s init  -backend-config=...
#   terraform -chdir=terraform/k3s apply -var="project_id=<PROJECT>"
#
# The k3s-ssh-private-key and k3s-ssh-public-key secrets are created
# automatically by Terraform (secrets.tf) — no manual action needed.
#
# Usage:
#   export PROJECT_ID=coinops
#   ./bootstrap/k3s-bootstrap.sh
# =============================================================================

set -euo pipefail

# ─── Color output ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()   { echo -e "${GREEN}[✓]${NC} $*"; }
info()  { echo -e "${CYAN}[i]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

# ─── Configuration ────────────────────────────────────────────────────────────
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
TOKEN_SECRET_ID="k3s-cluster-token"

[[ -z "$PROJECT_ID" ]] && error "PROJECT_ID is not set. Run: export PROJECT_ID=your-project-id"

info "Project: ${PROJECT_ID}"
info "Region:  ${REGION}"

# ─── 1. Enable Secret Manager API ────────────────────────────────────────────
info "Enabling Secret Manager API..."
gcloud services enable secretmanager.googleapis.com \
  --project="${PROJECT_ID}" \
  --quiet
log "Secret Manager API enabled."

# ─── 2. Create the token secret shell ────────────────────────────────────────
if gcloud secrets describe "${TOKEN_SECRET_ID}" \
    --project="${PROJECT_ID}" &>/dev/null; then
  warn "Secret '${TOKEN_SECRET_ID}' already exists. Checking for existing version..."

  EXISTING_VERSION=$(gcloud secrets versions list "${TOKEN_SECRET_ID}" \
    --project="${PROJECT_ID}" \
    --filter="state=ENABLED" \
    --format="value(name)" \
    --limit=1 2>/dev/null || true)

  if [[ -n "$EXISTING_VERSION" ]]; then
    warn "Secret version already exists. Skipping token generation."
    warn "To rotate: delete the existing version and re-run this script."
    log "Verifying token is readable..."
    gcloud secrets versions access latest \
      --secret="${TOKEN_SECRET_ID}" \
      --project="${PROJECT_ID}" \
      --quiet > /dev/null
    log "Token is readable. Bootstrap complete."
    exit 0
  fi
else
  info "Creating secret shell: ${TOKEN_SECRET_ID}"
  gcloud secrets create "${TOKEN_SECRET_ID}" \
    --project="${PROJECT_ID}" \
    --replication-policy="user-managed" \
    --locations="${REGION}" \
    --labels="managed-by=terraform,cluster=k3s-ha" \
    --quiet
  log "Secret shell created."
fi

# ─── 3. Generate a cryptographically secure token ────────────────────────────
info "Generating k3s cluster token..."
K3S_TOKEN=$(openssl rand -hex 48)
info "Token generated (48 bytes, hex-encoded)."

# ─── 4. Store as first secret version ────────────────────────────────────────
info "Storing token in Secret Manager..."
printf '%s' "${K3S_TOKEN}" | gcloud secrets versions add "${TOKEN_SECRET_ID}" \
  --project="${PROJECT_ID}" \
  --data-file=- \
  --quiet
log "Token stored as version 1."

# ─── 5. Verify ────────────────────────────────────────────────────────────────
info "Verifying token is readable..."
RETRIEVED=$(gcloud secrets versions access latest \
  --secret="${TOKEN_SECRET_ID}" \
  --project="${PROJECT_ID}")

[[ "$RETRIEVED" == "$K3S_TOKEN" ]] || error "Token verification failed — stored value does not match!"
log "Token verified successfully."

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  k3s Bootstrap Complete${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Secret:   projects/${PROJECT_ID}/secrets/${TOKEN_SECRET_ID}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo -e "  1. terraform -chdir=terraform/k3s init \\"
echo -e "       -backend-config=\"bucket=<STATE_BUCKET>\" \\"
echo -e "       -backend-config=\"prefix=terraform/k3s\""
echo -e "  2. terraform -chdir=terraform/k3s apply \\"
echo -e "       -var=\"project_id=${PROJECT_ID}\""
echo ""
warn "NEVER print or log the token value. It is now only in Secret Manager."
