'''
cd /Users/xiaofeng/Desktop/jumpserver

docker rm -f jms-openbao-1 jms-openbao-2 jms-openbao-3

rm -rf data/openbao-node1 data/openbao-node2 data/openbao-node3

export VAULT_OPENBAO_TOKEN=dev-root
export OPENBAO_NETWORK=jms-openbao-dev
export OPENBAO_UNSEAL_KEY_SHARES=5
export OPENBAO_UNSEAL_KEY_THRESHOLD=3



OPENBAO_CONTAINER=jms-openbao-1 \
OPENBAO_INIT_CONTAINER=jms-openbao-init-1 \
OPENBAO_NETWORK_ALIAS=openbao-1 \
OPENBAO_RUNTIME_DIR="$PWD/data/openbao-node1" \
OPENBAO_PORT=8200 \
OPENBAO_CLUSTER_PORT=8201 \
OPENBAO_RAFT_NODE_ID=openbao-1 \
OPENBAO_RAFT_BOOTSTRAP=true \
deploy/openbao/start-local.sh

mkdir -p data/openbao-node2/config data/openbao-node3/config

cp data/openbao-node1/config/init.json data/openbao-node2/config/init.json
cp data/openbao-node1/config/init.json data/openbao-node3/config/init.json



OPENBAO_CONTAINER=jms-openbao-2 \
OPENBAO_INIT_CONTAINER=jms-openbao-init-2 \
OPENBAO_NETWORK_ALIAS=openbao-2 \
OPENBAO_RUNTIME_DIR="$PWD/data/openbao-node2" \
OPENBAO_PORT=8210 \
OPENBAO_CLUSTER_PORT=8211 \
OPENBAO_RAFT_NODE_ID=openbao-2 \
OPENBAO_RAFT_BOOTSTRAP=false \
OPENBAO_RAFT_RETRY_JOIN=http://openbao-1:8200 \
deploy/openbao/start-local.sh



OPENBAO_CONTAINER=jms-openbao-3 \
OPENBAO_INIT_CONTAINER=jms-openbao-init-3 \
OPENBAO_NETWORK_ALIAS=openbao-3 \
OPENBAO_RUNTIME_DIR="$PWD/data/openbao-node3" \
OPENBAO_PORT=8220 \
OPENBAO_CLUSTER_PORT=8221 \
OPENBAO_RAFT_NODE_ID=openbao-3 \
OPENBAO_RAFT_BOOTSTRAP=false \
OPENBAO_RAFT_RETRY_JOIN=http://openbao-1:8200,http://openbao-2:8200 \
deploy/openbao/start-local.sh

ROOT_TOKEN=$(python3 -c 'import json; print(json.load(open("data/openbao-node1/config/init.json"))["root_token"])')

docker exec -e BAO_TOKEN="$ROOT_TOKEN" jms-openbao-1 \
  bao operator raft list-peers -address=http://127.0.0.1:8200






ROOT_TOKEN=$(python3 -c 'import json; print(json.load(open("data/openbao-node1/config/init.json"))["root_token"])')

unseal_node() {
  node="$1"
  python3 -c 'import json; d=json.load(open("data/openbao-node1/config/init.json")); print("\n".join(d["unseal_keys_b64"][:3]))' |
  while read key; do
    docker exec "$node" bao operator unseal -address=http://127.0.0.1:8200 "$key" >/dev/null
  done
}

status_node() {
  node="$1"
  echo "=== $node ==="
  docker exec "$node" bao status -address=http://127.0.0.1:8200 | egrep 'Sealed|HA Mode|Active Node Address|Active Since'
}

peers_from() {
  node="$1"
  docker exec -e BAO_TOKEN="$ROOT_TOKEN" "$node" \
    bao operator raft list-peers -address=http://127.0.0.1:8200
}



你刚才停了 node1，所以先恢复它：
docker start jms-openbao-1
unseal_node jms-openbao-1

status_node jms-openbao-1
status_node jms-openbao-2
status_node jms-openbao-3

确认 3 个节点都是：
Sealed false
然后看当前 leader：
peers_from jms-openbao-2
如果现在还是 openbao-2 leader，就停 node2：
docker stop jms-openbao-2
sleep 8
看 node1/node3 谁变 active：
status_node jms-openbao-1
status_node jms-openbao-3


预期是其中一个：
HA Mode active
另一个：
HA Mode standby
Active Node Address http://...
再从新的 active 节点查 peers。比如 node3 是 active：
peers_from jms-openbao-3
再测恢复 node2：
docker start jms-openbao-2
unseal_node jms-openbao-2
sleep 5

status_node jms-openbao-2
peers_from jms-openbao-3
恢复后的 node2 通常会是 follower/standby，不一定重新变 leader，这是正常的。
如果要顺便验证写入可用，可以在当前 active 节点上写一条：
docker exec -e BAO_TOKEN="$ROOT_TOKEN" jms-openbao-3 \
  bao kv put -address=http://127.0.0.1:8200 pam/failover-test secret=ok

'''