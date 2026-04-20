#!/usr/bin/env bash
set -euo pipefail
umask 077

# Keep reverse tunnel alive from bastion PC to relay server.
# Run this script ON the bastion PC (e.g. ihpc@192.168.50.196).
#
# Example:
#   RELAY_HOST=172.24.160.42 RELAY_USER=ihpc RELAY_SSH_PORT=20002 ./keep_reverse_tunnel.sh

RELAY_HOST="${RELAY_HOST:-172.24.160.42}"
RELAY_USER="${RELAY_USER:-ihpc}"
RELAY_SSH_PORT="${RELAY_SSH_PORT:-20002}"
RELAY_SSH_KEY="${RELAY_SSH_KEY:-${HOME}/.ssh/id_ed25519}"
RELAY_KNOWN_HOSTS="${RELAY_KNOWN_HOSTS:-${HOME}/.ssh/known_hosts}"
ALLOW_PASSWORD_AUTH="${ALLOW_PASSWORD_AUTH:-0}"

# Reverse endpoint created on relay server (loopback only).
REMOTE_REVERSE_HOST="${REMOTE_REVERSE_HOST:-127.0.0.1}"
REMOTE_REVERSE_PORT="${REMOTE_REVERSE_PORT:-28081}"

# Target service reachable from bastion PC.
TARGET_HOST="${TARGET_HOST:-192.168.50.138}"
TARGET_PORT="${TARGET_PORT:-80}"

# Reconnect interval when tunnel process exits.
RETRY_SECONDS="${RETRY_SECONDS:-5}"

# Safety guard: keep reverse endpoint loopback-only by default.
if [[ "${REMOTE_REVERSE_HOST}" != "127.0.0.1" && "${REMOTE_REVERSE_HOST}" != "localhost" ]]; then
  echo "ERROR: REMOTE_REVERSE_HOST must be 127.0.0.1 (current: ${REMOTE_REVERSE_HOST})."
  echo "Refusing to expose reverse tunnel on non-loopback interface."
  exit 1
fi

SSH_BASE_OPTS=(
  -N
  -T
  -p "${RELAY_SSH_PORT}"
  -o ExitOnForwardFailure=yes
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=3
  -o ConnectTimeout=10
  -o ForwardAgent=no
  -o RequestTTY=no
  -o PermitLocalCommand=no
  -o StrictHostKeyChecking=yes
  -o UserKnownHostsFile="${RELAY_KNOWN_HOSTS}"
)

if [[ "${ALLOW_PASSWORD_AUTH}" == "1" ]]; then
  SSH_BASE_OPTS+=(-o PreferredAuthentications=password -o PubkeyAuthentication=no)
else
  SSH_BASE_OPTS+=(-o BatchMode=yes -o PreferredAuthentications=publickey -o PubkeyAuthentication=yes -o IdentitiesOnly=yes)
  if [[ -f "${RELAY_SSH_KEY}" ]]; then
    SSH_BASE_OPTS+=(-i "${RELAY_SSH_KEY}")
  else
    echo "ERROR: SSH key not found: ${RELAY_SSH_KEY}"
    echo "Set RELAY_SSH_KEY to your key path, or ALLOW_PASSWORD_AUTH=1 for password mode."
    exit 1
  fi
fi

echo "=== Reverse Tunnel Keeper ==="
echo "relay:   ${RELAY_USER}@${RELAY_HOST}:${RELAY_SSH_PORT}"
echo "remote:  ${REMOTE_REVERSE_HOST}:${REMOTE_REVERSE_PORT} (on relay)"
echo "target:  ${TARGET_HOST}:${TARGET_PORT} (from bastion)"
echo "retry:   ${RETRY_SECONDS}s"
echo

if command -v autossh >/dev/null 2>&1; then
  echo "[mode] autossh (auto-reconnect)"
  exec autossh -M 0 \
    "${SSH_BASE_OPTS[@]}" \
    -R "${REMOTE_REVERSE_HOST}:${REMOTE_REVERSE_PORT}:${TARGET_HOST}:${TARGET_PORT}" \
    "${RELAY_USER}@${RELAY_HOST}"
fi

echo "[mode] ssh loop (autossh not found)"
while true; do
  echo "[connect] $(date '+%Y-%m-%d %H:%M:%S')"
  if ssh \
    "${SSH_BASE_OPTS[@]}" \
    -R "${REMOTE_REVERSE_HOST}:${REMOTE_REVERSE_PORT}:${TARGET_HOST}:${TARGET_PORT}" \
    "${RELAY_USER}@${RELAY_HOST}"; then
    echo "[exit] tunnel command ended normally"
  else
    rc=$?
    echo "[warn] tunnel disconnected (rc=${rc})"
  fi

  echo "[retry] reconnecting in ${RETRY_SECONDS}s..."
  sleep "${RETRY_SECONDS}"
done
