#!/bin/sh
set -eu
set -f

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

OPENBAO_HAPROXY_BACKENDS="${OPENBAO_HAPROXY_BACKENDS:-}"
OPENBAO_HAPROXY_IMAGE="${OPENBAO_HAPROXY_IMAGE:-haproxy:3.0-alpine}"
OPENBAO_HAPROXY_CONTAINER="${OPENBAO_HAPROXY_CONTAINER:-jms-openbao-haproxy}"
OPENBAO_HAPROXY_PORT="${OPENBAO_HAPROXY_PORT:-8200}"
OPENBAO_HAPROXY_BIND="${OPENBAO_HAPROXY_BIND:-0.0.0.0}"
OPENBAO_HAPROXY_NETWORK="${OPENBAO_HAPROXY_NETWORK:-jms-openbao-ha}"
OPENBAO_HA_DRY_RUN="${OPENBAO_HA_DRY_RUN:-false}"

OPENBAO_HA_RUNTIME_DIR="${OPENBAO_HA_RUNTIME_DIR:-${BASE_DIR}/data/openbao-ha}"
OPENBAO_KEEPALIVED_ENABLED="${OPENBAO_KEEPALIVED_ENABLED:-true}"
OPENBAO_KEEPALIVED_IMAGE="${OPENBAO_KEEPALIVED_IMAGE:-jms-openbao-keepalived:1.0}"
OPENBAO_KEEPALIVED_CONTAINER="${OPENBAO_KEEPALIVED_CONTAINER:-jms-openbao-keepalived}"
OPENBAO_KEEPALIVED_DOCKERFILE="${OPENBAO_KEEPALIVED_DOCKERFILE:-${BASE_DIR}/deploy/openbao/keepalived/Dockerfile}"
OPENBAO_KEEPALIVED_INTERFACE="${OPENBAO_KEEPALIVED_INTERFACE:-}"
OPENBAO_KEEPALIVED_STATE="${OPENBAO_KEEPALIVED_STATE:-}"
OPENBAO_KEEPALIVED_PRIORITY="${OPENBAO_KEEPALIVED_PRIORITY:-}"
OPENBAO_KEEPALIVED_ROUTER_ID="${OPENBAO_KEEPALIVED_ROUTER_ID:-51}"
OPENBAO_KEEPALIVED_LOCAL_IP="${OPENBAO_KEEPALIVED_LOCAL_IP:-}"
OPENBAO_KEEPALIVED_PEER_IP="${OPENBAO_KEEPALIVED_PEER_IP:-}"
OPENBAO_KEEPALIVED_VIP="${OPENBAO_KEEPALIVED_VIP:-}"
OPENBAO_KEEPALIVED_AUTH_PASS="${OPENBAO_KEEPALIVED_AUTH_PASS:-}"

die() {
  echo "Error: $*" >&2
  exit 1
}

is_true() {
  case "$1" in
    1|true|True|TRUE|yes|Yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

validate_backends() {
  [ -n "${OPENBAO_HAPROXY_BACKENDS}" ] || die "Set OPENBAO_HAPROXY_BACKENDS to comma-separated host:port values."
  case "${OPENBAO_HAPROXY_PORT}" in
    ''|*[!0-9]*) die "OPENBAO_HAPROXY_PORT must be numeric." ;;
  esac
  case "${OPENBAO_HAPROXY_BIND}" in
    *[!0-9A-Fa-f.:]*) die "OPENBAO_HAPROXY_BIND must be an IP address." ;;
  esac

  old_ifs="${IFS}"
  IFS=','
  set -- ${OPENBAO_HAPROXY_BACKENDS}
  IFS="${old_ifs}"

  [ "$#" -gt 0 ] || die "No OpenBao backends were provided."
  for backend in "$@"; do
    case "${backend}" in
      ''|*[!0-9A-Za-z.:[\]-]*) die "Invalid OpenBao backend: ${backend}" ;;
    esac
  done
}

validate_keepalived() {
  case "${OPENBAO_KEEPALIVED_STATE}" in
    MASTER|BACKUP) ;;
    *) die "OPENBAO_KEEPALIVED_STATE must be MASTER or BACKUP." ;;
  esac

  [ -n "${OPENBAO_KEEPALIVED_INTERFACE}" ] || die "Set OPENBAO_KEEPALIVED_INTERFACE."
  [ -n "${OPENBAO_KEEPALIVED_LOCAL_IP}" ] || die "Set OPENBAO_KEEPALIVED_LOCAL_IP."
  [ -n "${OPENBAO_KEEPALIVED_PEER_IP}" ] || die "Set OPENBAO_KEEPALIVED_PEER_IP."
  [ -n "${OPENBAO_KEEPALIVED_VIP}" ] || die "Set OPENBAO_KEEPALIVED_VIP as address/prefix."
  [ -n "${OPENBAO_KEEPALIVED_AUTH_PASS}" ] || die "Set OPENBAO_KEEPALIVED_AUTH_PASS."

  case "${OPENBAO_KEEPALIVED_PRIORITY}" in
    ''|*[!0-9]*) die "OPENBAO_KEEPALIVED_PRIORITY must be numeric." ;;
  esac
  case "${OPENBAO_KEEPALIVED_ROUTER_ID}" in
    ''|*[!0-9]*) die "OPENBAO_KEEPALIVED_ROUTER_ID must be numeric." ;;
  esac
  case "${OPENBAO_KEEPALIVED_VIP}" in
    */*) ;;
    *) die "OPENBAO_KEEPALIVED_VIP must include its network prefix, for example 10.0.0.100/24." ;;
  esac
  case "${OPENBAO_KEEPALIVED_INTERFACE}" in
    *[!0-9A-Za-z_.-]*) die "OPENBAO_KEEPALIVED_INTERFACE contains unsupported characters." ;;
  esac
  case "${OPENBAO_KEEPALIVED_LOCAL_IP}" in
    *[!0-9A-Fa-f.:]*) die "OPENBAO_KEEPALIVED_LOCAL_IP must be an IP address." ;;
  esac
  case "${OPENBAO_KEEPALIVED_PEER_IP}" in
    *[!0-9A-Fa-f.:]*) die "OPENBAO_KEEPALIVED_PEER_IP must be an IP address." ;;
  esac
  case "${OPENBAO_KEEPALIVED_VIP}" in
    *[!0-9A-Fa-f.:/]*) die "OPENBAO_KEEPALIVED_VIP must be an IP address with a prefix." ;;
  esac
  case "${OPENBAO_KEEPALIVED_AUTH_PASS}" in
    *[!0-9A-Za-z]*) die "OPENBAO_KEEPALIVED_AUTH_PASS may contain only letters and digits." ;;
  esac
  [ "${#OPENBAO_KEEPALIVED_AUTH_PASS}" -le 8 ] || die "OPENBAO_KEEPALIVED_AUTH_PASS must not exceed 8 characters."
}

write_haproxy_config() {
  config_file="${OPENBAO_HA_RUNTIME_DIR}/haproxy.cfg"

  cat >"${config_file}" <<'EOF'
global
  log stdout format raw local0

defaults
  mode http
  timeout connect 5s
  timeout client  30s
  timeout server  30s

resolvers docker
  nameserver dns 127.0.0.11:53
  resolve_retries 3
  timeout resolve 1s
  timeout retry   1s
  hold valid      10s

frontend openbao
  bind :8200
  default_backend openbao_nodes

backend openbao_nodes
  option httpchk
  http-check send meth GET uri /v1/sys/health ver HTTP/1.1 hdr Host openbao
  http-check expect status 200
EOF

  old_ifs="${IFS}"
  IFS=','
  set -- ${OPENBAO_HAPROXY_BACKENDS}
  IFS="${old_ifs}"

  index=1
  for backend in "$@"; do
    printf '  server openbao-%s %s check resolvers docker init-addr last,libc,none inter 2s fall 2 rise 2\n' \
      "${index}" "${backend}" >>"${config_file}"
    index=$((index + 1))
  done
}

start_haproxy() {
  docker network create "${OPENBAO_HAPROXY_NETWORK}" >/dev/null 2>&1 || true
  docker rm -f "${OPENBAO_HAPROXY_CONTAINER}" >/dev/null 2>&1 || true
  docker run -d \
    --name "${OPENBAO_HAPROXY_CONTAINER}" \
    --restart unless-stopped \
    --network "${OPENBAO_HAPROXY_NETWORK}" \
    -p "${OPENBAO_HAPROXY_BIND}:${OPENBAO_HAPROXY_PORT}:8200" \
    -v "${OPENBAO_HA_RUNTIME_DIR}/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro" \
    "${OPENBAO_HAPROXY_IMAGE}" \
    haproxy -f /usr/local/etc/haproxy/haproxy.cfg >/dev/null
}

write_keepalived_config() {
  config_file="${OPENBAO_HA_RUNTIME_DIR}/keepalived.conf"

  cat >"${config_file}" <<EOF
global_defs {
  router_id OPENBAO_HA
  enable_script_security
  script_user root
}

vrrp_script check_haproxy {
  script "/usr/bin/curl --fail --silent --max-time 2 http://127.0.0.1:${OPENBAO_HAPROXY_PORT}/v1/sys/health"
  interval 2
  timeout 2
  fall 2
  rise 2
  weight -100
}

vrrp_instance OPENBAO_HA {
  state ${OPENBAO_KEEPALIVED_STATE}
  interface ${OPENBAO_KEEPALIVED_INTERFACE}
  virtual_router_id ${OPENBAO_KEEPALIVED_ROUTER_ID}
  priority ${OPENBAO_KEEPALIVED_PRIORITY}
  advert_int 1

  authentication {
    auth_type PASS
    auth_pass ${OPENBAO_KEEPALIVED_AUTH_PASS}
  }

  unicast_src_ip ${OPENBAO_KEEPALIVED_LOCAL_IP}
  unicast_peer {
    ${OPENBAO_KEEPALIVED_PEER_IP}
  }

  virtual_ipaddress {
    ${OPENBAO_KEEPALIVED_VIP} dev ${OPENBAO_KEEPALIVED_INTERFACE}
  }

  track_script {
    check_haproxy
  }
}
EOF
}

start_keepalived() {
  [ -f "${OPENBAO_KEEPALIVED_DOCKERFILE}" ] || die "Keepalived Dockerfile not found: ${OPENBAO_KEEPALIVED_DOCKERFILE}"

  if ! docker image inspect "${OPENBAO_KEEPALIVED_IMAGE}" >/dev/null 2>&1; then
    docker build \
      --tag "${OPENBAO_KEEPALIVED_IMAGE}" \
      --file "${OPENBAO_KEEPALIVED_DOCKERFILE}" \
      "$(dirname "${OPENBAO_KEEPALIVED_DOCKERFILE}")"
  fi

  docker rm -f "${OPENBAO_KEEPALIVED_CONTAINER}" >/dev/null 2>&1 || true
  docker run -d \
    --name "${OPENBAO_KEEPALIVED_CONTAINER}" \
    --restart unless-stopped \
    --network host \
    --cap-add NET_ADMIN \
    --cap-add NET_BROADCAST \
    --cap-add NET_RAW \
    -v "${OPENBAO_HA_RUNTIME_DIR}/keepalived.conf:/etc/keepalived/keepalived.conf:ro" \
    "${OPENBAO_KEEPALIVED_IMAGE}" >/dev/null
}

main() {
  umask 077
  validate_backends

  if is_true "${OPENBAO_KEEPALIVED_ENABLED}"; then
    validate_keepalived
  fi

  mkdir -p "${OPENBAO_HA_RUNTIME_DIR}"
  write_haproxy_config
  if is_true "${OPENBAO_KEEPALIVED_ENABLED}"; then
    write_keepalived_config
  fi

  if ! is_true "${OPENBAO_HA_DRY_RUN}"; then
    start_haproxy
  fi
  if is_true "${OPENBAO_KEEPALIVED_ENABLED}" && ! is_true "${OPENBAO_HA_DRY_RUN}"; then
    start_keepalived
  fi

  if is_true "${OPENBAO_KEEPALIVED_ENABLED}"; then
    vault_config="VAULT_OPENBAO_ADDR=http://${OPENBAO_KEEPALIVED_VIP%/*}:${OPENBAO_HAPROXY_PORT}"
    vip="${OPENBAO_KEEPALIVED_VIP}"
  else
    vault_config="# Set VAULT_OPENBAO_ADDR to this HAProxy host address."
    vip="disabled"
  fi

  cat <<EOF
OpenBao HA ingress is ready.
Backends: ${OPENBAO_HAPROXY_BACKENDS}
HAProxy:  http://${OPENBAO_HAPROXY_BIND}:${OPENBAO_HAPROXY_PORT}
VIP:      ${vip}
Dry run:  ${OPENBAO_HA_DRY_RUN}

Set this on every JumpServer node:
${vault_config}
EOF
}

main "$@"
