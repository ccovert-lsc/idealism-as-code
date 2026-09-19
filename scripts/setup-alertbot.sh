#!/bin/bash
# Set up the matrix-alertmanager bridge.
#
# Creates a Matrix access token for the alertbot user, creates the alerts room,
# stores both in a k8s secret, and deploys the alertmanager webhook bridge.
#
# Prerequisites:
#   - Synapse running and the alertbot user already registered:
#       kubectl exec -n matrix-auth deploy/mas -- \
#         mas-cli manage register-user -u alertbot
#   - matrix-alertmanager namespace exists
#     (kubectl apply -f kubernetes/apps/matrix-alertmanager/namespace.yaml)
#
# Run from mgmt-01: bash ~/lab-work/scripts/setup-alertbot.sh
set -e
export KUBECONFIG="${KUBECONFIG:-/home/ubuntu/.kube/lab.yaml}"

# --- Config: adapt to your environment ---
MATRIX_URL="https://matrix.example.com"
ALERTBOT_USER="alertbot"
ALERTBOT_PASSWORD="${ALERTBOT_PASSWORD:?Set ALERTBOT_PASSWORD env var}"
BRIDGE_MANIFEST="$HOME/lab-work/kubernetes/apps/matrix-alertmanager/bridge.yaml"

echo "=== Getting alertbot access token ==="
ACCESS_TOKEN=$(curl -s -X POST "${MATRIX_URL}/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"m.login.password\",\"user\":\"${ALERTBOT_USER}\",\"password\":\"${ALERTBOT_PASSWORD}\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
echo "Token obtained: ${ACCESS_TOKEN:0:20}..."

echo "=== Creating alerts room ==="
ROOM_ID=$(curl -s -X POST "${MATRIX_URL}/_matrix/client/v3/createRoom" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Alerts","topic":"Alertmanager notifications","preset":"private_chat"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['room_id'])")
echo "Room ID: $ROOM_ID"

echo "=== Storing k8s secret ==="
printf "%s" "@${ALERTBOT_USER}:example.com" > /tmp/uid.txt
printf "%s" "$ACCESS_TOKEN"                 > /tmp/token.txt
printf "%s" "$ROOM_ID"                      > /tmp/roomid.txt

kubectl create secret generic matrix-alertmanager-secrets -n matrix-alertmanager \
  --from-file=user_id=/tmp/uid.txt \
  --from-file=access_token=/tmp/token.txt \
  --from-file=room_id=/tmp/roomid.txt \
  --dry-run=client -o yaml | kubectl apply -f -

rm /tmp/uid.txt /tmp/token.txt /tmp/roomid.txt

echo "=== Deploying bridge ==="
kubectl apply -f "$BRIDGE_MANIFEST"

echo ""
echo "=== Done ==="
echo "Room ID (invite yourself in Element): $ROOM_ID"
