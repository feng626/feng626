#!/bin/sh
set -eu

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

OPENBAO_NETWORK="${OPENBAO_NETWORK:-jms-openbao-dev}"
OPENBAO_HAPROXY_IMAGE="${OPENBAO_HAPROXY_IMAGE:-haproxy:3.0-alpine}"
OPENBAO_HAPROXY_CONTAINER="${OPENBAO_HAPROXY_CONTAINER:-jms-openbao-haproxy}"
OPENBAO_HAPROXY_PORT="${OPENBAO_HAPROXY_PORT:-8230}"
OPENBAO_HAPROXY_CONFIG="${OPENBAO_HAPROXY_CONFIG:-${BASE_DIR}/deploy/openbao/haproxy.cfg}"

if [ ! -f "${OPENBAO_HAPROXY_CONFIG}" ]; then
  echo "HAProxy config not found: ${OPENBAO_HAPROXY_CONFIG}"
  exit 1
fi

docker network create "${OPENBAO_NETWORK}" >/dev/null 2>&1 || true
docker rm -f "${OPENBAO_HAPROXY_CONTAINER}" >/dev/null 2>&1 || true
docker run -d \
  --name "${OPENBAO_HAPROXY_CONTAINER}" \
  --network "${OPENBAO_NETWORK}" \
  -p "${OPENBAO_HAPROXY_PORT}:8200" \
  -v "${OPENBAO_HAPROXY_CONFIG}:/usr/local/etc/haproxy/haproxy.cfg:ro" \
  "${OPENBAO_HAPROXY_IMAGE}" \
  haproxy -f /usr/local/etc/haproxy/haproxy.cfg >/dev/null

cat <<EOF
OpenBao HAProxy is ready: http://127.0.0.1:${OPENBAO_HAPROXY_PORT}

JumpServer config.yml:
VAULT_OPENBAO_ADDR: http://127.0.0.1:${OPENBAO_HAPROXY_PORT}
EOF
