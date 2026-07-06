#!/usr/bin/env bash
#
# init-env — provision a host for compose-over-SSH deployments.
#
# Codifies the one-time VPS bootstrap used by action-library's deploy-compose:
#   1. create a deploy user (home + shell)
#   2. add it to the docker group
#   3. authorize a deploy SSH public key
#   4. create the deployment root (/home/<user>/deployment)
#
# Idempotent — safe to re-run. Must run as root on the target host.
#
# Usage:
#   sudo ./init-env.sh --pubkey "ssh-ed25519 AAAA... deploy@ci"
#   sudo ./init-env.sh -u apexvoid -f deploy_key.pub
#   cat deploy_key.pub | sudo ./init-env.sh          # key on stdin
#
# Options:
#   -u, --user USER          deploy user            (default: apexvoid)
#   -k, --pubkey "KEY..."    SSH public key string to authorize
#   -f, --pubkey-file PATH   read the public key from a file
#   -d, --deploy-root PATH   deployment root        (default: /home/<user>/deployment)
#   -g, --docker-group NAME  docker group           (default: docker)
#   -h, --help               show this help
#
set -euo pipefail

USER_NAME="apexvoid"
PUBKEY=""
PUBKEY_FILE=""
DEPLOY_ROOT=""
DOCKER_GROUP="docker"

die() { echo "init-env: $*" >&2; exit 1; }
usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    -u|--user)         USER_NAME="${2:?}"; shift 2 ;;
    -k|--pubkey)       PUBKEY="${2:?}"; shift 2 ;;
    -f|--pubkey-file)  PUBKEY_FILE="${2:?}"; shift 2 ;;
    -d|--deploy-root)  DEPLOY_ROOT="${2:?}"; shift 2 ;;
    -g|--docker-group) DOCKER_GROUP="${2:?}"; shift 2 ;;
    -h|--help)         usage 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "must run as root"

# Resolve the public key: flag > file > stdin (if piped).
if [ -z "$PUBKEY" ] && [ -n "$PUBKEY_FILE" ]; then
  [ -r "$PUBKEY_FILE" ] || die "cannot read pubkey file: $PUBKEY_FILE"
  PUBKEY="$(cat "$PUBKEY_FILE")"
fi
if [ -z "$PUBKEY" ] && [ ! -t 0 ]; then
  PUBKEY="$(cat)"
fi
[ -n "$PUBKEY" ] || die "no SSH public key given (use --pubkey, --pubkey-file, or stdin)"
case "$PUBKEY" in
  ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*\ *|sk-*) : ;;
  *) die "value does not look like an SSH public key" ;;
esac

: "${DEPLOY_ROOT:=/home/$USER_NAME/deployment}"

# 1. deploy user
if id "$USER_NAME" >/dev/null 2>&1; then
  echo "user $USER_NAME: exists"
else
  useradd -m -s /bin/bash "$USER_NAME"
  echo "user $USER_NAME: created"
fi

# 2. docker group membership
if ! getent group "$DOCKER_GROUP" >/dev/null; then
  groupadd "$DOCKER_GROUP"
  echo "group $DOCKER_GROUP: created (docker may not be installed yet)"
fi
usermod -aG "$DOCKER_GROUP" "$USER_NAME"
echo "user $USER_NAME: in group $DOCKER_GROUP"

# 3. authorize deploy key
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$HOME_DIR/.ssh"
AUTH_KEYS="$HOME_DIR/.ssh/authorized_keys"
touch "$AUTH_KEYS"
if grep -qxF "$PUBKEY" "$AUTH_KEYS"; then
  echo "authorized_keys: key already present"
else
  printf '%s\n' "$PUBKEY" >> "$AUTH_KEYS"
  echo "authorized_keys: key added"
fi
chmod 600 "$AUTH_KEYS"
chown "$USER_NAME:$USER_NAME" "$AUTH_KEYS"

# 4. deployment root
install -d -m 755 -o "$USER_NAME" -g "$USER_NAME" "$DEPLOY_ROOT"
echo "deployment root: $DEPLOY_ROOT"

echo
echo "=== done ==="
id "$USER_NAME"
ls -ld "$HOME_DIR/.ssh" "$AUTH_KEYS" "$DEPLOY_ROOT"
echo
echo "Next: put the matching PRIVATE key in the repo secret DEPLOY_SSH_KEY,"
echo "and set variables DEPLOY_HOST / DEPLOY_USER=$USER_NAME / DEPLOY_PORT."
