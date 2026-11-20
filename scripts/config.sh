# Shared settings for the Mac-side scripts. Source this file; do not execute it.
# zsh/bash compatible. Always use ${VAR} braces (zsh treats $A:r as a modifier).
export AWS_PROFILE_NAME="nuget-harness"
export AWS_REGION_NAME="ap-southeast-2"
AWSP=(--profile "${AWS_PROFILE_NAME}" --region "${AWS_REGION_NAME}")

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${HARNESS_ROOT}/.state"
KEY_PATH="${HOME}/.ssh/nuget-harness"
KEY_NAME="nuget-harness"
SG_NAME="nuget-harness-ssh"
INSTANCE_NAME="nuget-harness-old-app"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.large}"
ROOT_GB=100
AMI_PARAM="/aws/service/ami-windows-latest/Windows_Server-2025-English-Full-Base"
# Local tunnel ports (443 may be refused on some macOS setups; override with LOCAL_HTTPS_PORT).
LOCAL_HTTPS_PORT="${LOCAL_HTTPS_PORT:-443}"
LOCAL_SQL_PORT="${LOCAL_SQL_PORT:-1433}"
mkdir -p "${STATE_DIR}"

instance_id() { cat "${STATE_DIR}/instance-id" 2>/dev/null; }
instance_ip() {
  aws ec2 describe-instances "${AWSP[@]}" --instance-ids "$(instance_id)" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
}
SSH_OPTS=(-i "${KEY_PATH}" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new
          -o UserKnownHostsFile="${STATE_DIR}/known_hosts" -o ConnectTimeout=15
          -o ServerAliveInterval=30 -o ServerAliveCountMax=6)
# Run a PowerShell command string on the server.
rsh() { ssh "${SSH_OPTS[@]}" "Administrator@$(instance_ip)" "$@"; }
# Copy local files to a server path (scp uses the same key).
rcp() { local dest="$1"; shift; scp -q "${SSH_OPTS[@]}" "$@" "Administrator@$(instance_ip):${dest}"; }
log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
