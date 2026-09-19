#!/bin/bash
# Set up a self-hosted GitHub Actions runner on mgmt-01.
#
# The runner makes outbound connections only — no inbound ports required.
# It enables: tofu plan on PR, tofu apply on merge to main.
#
# Get the registration token from:
#   https://github.com/<org>/<repo>/settings/actions/runners/new
#   Settings → Actions → Runners → New self-hosted runner → copy the token
#
# Run on mgmt-01: bash ~/lab-work/scripts/setup-github-runner.sh <GITHUB_RUNNER_TOKEN>
set -euo pipefail

TOKEN="${1:?Usage: $0 <GITHUB_RUNNER_TOKEN>}"
RUNNER_VERSION="2.322.0"
RUNNER_DIR="$HOME/actions-runner"

# --- Config: adapt to your environment ---
REPO_URL="https://github.com/<your-org>/<your-repo>"
RUNNER_NAME="mgmt-01"
RUNNER_LABELS="self-hosted,linux,mgmt-01"

echo "==> Installing runner $RUNNER_VERSION..."
mkdir -p "$RUNNER_DIR" && cd "$RUNNER_DIR"

curl -sL "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
  | tar xz

echo "==> Configuring runner for $REPO_URL..."
./config.sh \
  --url "$REPO_URL" \
  --token "$TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$RUNNER_LABELS" \
  --work "$HOME/actions-runner/_work" \
  --unattended

echo "==> Installing as systemd service..."
sudo ./svc.sh install
sudo ./svc.sh start

echo "==> Runner status:"
sudo ./svc.sh status

echo ""
echo "Done. Runner '$RUNNER_NAME' is registered and running."
echo "View at: ${REPO_URL}/settings/actions/runners"
