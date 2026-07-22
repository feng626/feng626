# OpenBao 线上高可用部署示例

本文给出一套完整、可按顺序执行的示例。OpenBao 节点与代理机均已安装 Docker，
并已将 JumpServer 源码放在 `/opt/jumpserver/jumpserver`。

## 1. 示例拓扑

| 角色 | 地址 | 说明 |
| --- | --- | --- |
| JumpServer | `10.0.0.10` | 运行 Core、Celery 等服务 |
| OpenBao 1 | `10.0.0.11` | 第一个 Raft 节点 |
| OpenBao 2 | `10.0.0.12` | 第二个 Raft 节点 |
| OpenBao 3 | `10.0.0.13` | 第三个 Raft 节点 |
| HAProxy 1 | `10.0.0.21` | Keepalived MASTER |
| HAProxy 2 | `10.0.0.22` | Keepalived BACKUP |
| OpenBao VIP | `10.0.0.20` | Core 永久连接的地址 |

两台代理机必须位于 VIP 所属二层网络。本示例网卡名为 `ens160`，实际部署时必须改成服务器的真实网卡名。

网络至少需要满足：

- 三台 OpenBao 之间互通 TCP `8200`、`8201`。
- 两台代理机可以访问三台 OpenBao 的 TCP `8200`。
- JumpServer 可以访问 VIP 的 TCP `8200`。
- 两台代理机之间允许 VRRP，即 IP 协议号 `112`。

## 2. 准备公共参数

生成一个 JumpServer 专用的 OpenBao Service Token。下面的值必须安全保存，并在三台 OpenBao
和 JumpServer Core 中保持完全一致：

```bash
openssl rand -hex 24
```

下文用 `REPLACE_WITH_SAME_SERVICE_TOKEN` 表示该值，不要直接使用这个占位字符串。

## 3. 启动 OpenBao 1

在 `10.0.0.11` 执行：

```bash
cd /opt/jumpserver/jumpserver

export VAULT_OPENBAO_TOKEN='REPLACE_WITH_SAME_SERVICE_TOKEN'
export VAULT_OPENBAO_MOUNT_POINT=pam
export OPENBAO_NETWORK=jms-openbao-prod
export OPENBAO_CONTAINER=jms-openbao
export OPENBAO_INIT_CONTAINER=jms-openbao-init
export OPENBAO_NETWORK_ALIAS=openbao
export OPENBAO_RUNTIME_DIR=/opt/jumpserver/openbao
export OPENBAO_PORT=8200
export OPENBAO_CLUSTER_PORT=8201
export OPENBAO_UNSEAL_KEY_SHARES=5
export OPENBAO_UNSEAL_KEY_THRESHOLD=3

OPENBAO_RAFT_NODE_ID=openbao-1 \
OPENBAO_RAFT_API_ADDR=http://10.0.0.11:8200 \
OPENBAO_RAFT_CLUSTER_ADDR=http://10.0.0.11:8201 \
OPENBAO_RAFT_BOOTSTRAP=true \
deploy/openbao/start-local.sh
```

首次初始化后会生成：

```text
/opt/jumpserver/openbao/config/init.json
```

该文件包含 Root Token 和 Unseal Key，权限必须保持为 `600`，不能提交到 Git、日志或普通文件共享系统。

## 4. 分发初始化文件

先在 `10.0.0.12` 和 `10.0.0.13` 创建目录：

```bash
mkdir -p /opt/jumpserver/openbao/config
chmod 700 /opt/jumpserver/openbao/config
```

然后从 `10.0.0.11` 安全复制：

```bash
scp /opt/jumpserver/openbao/config/init.json root@10.0.0.12:/opt/jumpserver/openbao/config/init.json
scp /opt/jumpserver/openbao/config/init.json root@10.0.0.13:/opt/jumpserver/openbao/config/init.json
ssh root@10.0.0.12 chmod 600 /opt/jumpserver/openbao/config/init.json
ssh root@10.0.0.13 chmod 600 /opt/jumpserver/openbao/config/init.json
```

## 5. 启动 OpenBao 2

在 `10.0.0.12` 执行：

```bash
cd /opt/jumpserver/jumpserver

export VAULT_OPENBAO_TOKEN='REPLACE_WITH_SAME_SERVICE_TOKEN'
export VAULT_OPENBAO_MOUNT_POINT=pam
export OPENBAO_NETWORK=jms-openbao-prod
export OPENBAO_CONTAINER=jms-openbao
export OPENBAO_INIT_CONTAINER=jms-openbao-init
export OPENBAO_NETWORK_ALIAS=openbao
export OPENBAO_RUNTIME_DIR=/opt/jumpserver/openbao
export OPENBAO_PORT=8200
export OPENBAO_CLUSTER_PORT=8201
export OPENBAO_UNSEAL_KEY_SHARES=5
export OPENBAO_UNSEAL_KEY_THRESHOLD=3

OPENBAO_RAFT_NODE_ID=openbao-2 \
OPENBAO_RAFT_API_ADDR=http://10.0.0.12:8200 \
OPENBAO_RAFT_CLUSTER_ADDR=http://10.0.0.12:8201 \
OPENBAO_RAFT_RETRY_JOIN=http://10.0.0.11:8200 \
OPENBAO_RAFT_BOOTSTRAP=false \
deploy/openbao/start-local.sh
```

## 6. 启动 OpenBao 3

在 `10.0.0.13` 执行：

```bash
cd /opt/jumpserver/jumpserver

export VAULT_OPENBAO_TOKEN='REPLACE_WITH_SAME_SERVICE_TOKEN'
export VAULT_OPENBAO_MOUNT_POINT=pam
export OPENBAO_NETWORK=jms-openbao-prod
export OPENBAO_CONTAINER=jms-openbao
export OPENBAO_INIT_CONTAINER=jms-openbao-init
export OPENBAO_NETWORK_ALIAS=openbao
export OPENBAO_RUNTIME_DIR=/opt/jumpserver/openbao
export OPENBAO_PORT=8200
export OPENBAO_CLUSTER_PORT=8201
export OPENBAO_UNSEAL_KEY_SHARES=5
export OPENBAO_UNSEAL_KEY_THRESHOLD=3

OPENBAO_RAFT_NODE_ID=openbao-3 \
OPENBAO_RAFT_API_ADDR=http://10.0.0.13:8200 \
OPENBAO_RAFT_CLUSTER_ADDR=http://10.0.0.13:8201 \
OPENBAO_RAFT_RETRY_JOIN=http://10.0.0.11:8200,http://10.0.0.12:8200 \
OPENBAO_RAFT_BOOTSTRAP=false \
deploy/openbao/start-local.sh
```

## 7. 验证 Raft 集群

在任意 OpenBao 节点执行，下面以 `10.0.0.11` 为例：

```bash
ROOT_TOKEN=$(python3 -c 'import json; print(json.load(open("/opt/jumpserver/openbao/config/init.json"))["root_token"])')

docker exec -e BAO_TOKEN="$ROOT_TOKEN" jms-openbao \
  bao operator raft list-peers -address=http://127.0.0.1:8200
```

必须看到三个节点，其中一个状态为 `leader`，另外两个为 `follower`。未达到三个节点前，不要继续部署代理和 Core。

## 8. 启动主 HAProxy/Keepalived

在 `10.0.0.21` 创建 `/etc/jumpserver/openbao-ha.env`：

```ini
OPENBAO_HAPROXY_BACKENDS=10.0.0.11:8200,10.0.0.12:8200,10.0.0.13:8200
OPENBAO_HAPROXY_PORT=8200
OPENBAO_HAPROXY_BIND=0.0.0.0
OPENBAO_HA_RUNTIME_DIR=/opt/jumpserver/config/openbao-ha

OPENBAO_KEEPALIVED_ENABLED=true
OPENBAO_KEEPALIVED_INTERFACE=ens160
OPENBAO_KEEPALIVED_STATE=MASTER
OPENBAO_KEEPALIVED_PRIORITY=150
OPENBAO_KEEPALIVED_ROUTER_ID=51
OPENBAO_KEEPALIVED_LOCAL_IP=10.0.0.21
OPENBAO_KEEPALIVED_PEER_IP=10.0.0.22
OPENBAO_KEEPALIVED_VIP=10.0.0.20/24
OPENBAO_KEEPALIVED_AUTH_PASS=BaoHA051
```

设置权限并启动：

```bash
chmod 600 /etc/jumpserver/openbao-ha.env
cd /opt/jumpserver/jumpserver
set -a
. /etc/jumpserver/openbao-ha.env
set +a
deploy/openbao/start-ha.sh
```

## 9. 启动备 HAProxy/Keepalived

在 `10.0.0.22` 创建 `/etc/jumpserver/openbao-ha.env`。后端、VIP、Router ID 和认证密码与主代理一致，
只交换本机/对端地址，并降低优先级：

```ini
OPENBAO_HAPROXY_BACKENDS=10.0.0.11:8200,10.0.0.12:8200,10.0.0.13:8200
OPENBAO_HAPROXY_PORT=8200
OPENBAO_HAPROXY_BIND=0.0.0.0
OPENBAO_HA_RUNTIME_DIR=/opt/jumpserver/config/openbao-ha

OPENBAO_KEEPALIVED_ENABLED=true
OPENBAO_KEEPALIVED_INTERFACE=ens160
OPENBAO_KEEPALIVED_STATE=BACKUP
OPENBAO_KEEPALIVED_PRIORITY=100
OPENBAO_KEEPALIVED_ROUTER_ID=51
OPENBAO_KEEPALIVED_LOCAL_IP=10.0.0.22
OPENBAO_KEEPALIVED_PEER_IP=10.0.0.21
OPENBAO_KEEPALIVED_VIP=10.0.0.20/24
OPENBAO_KEEPALIVED_AUTH_PASS=BaoHA051
```

启动命令与主代理相同：

```bash
chmod 600 /etc/jumpserver/openbao-ha.env
cd /opt/jumpserver/jumpserver
set -a
. /etc/jumpserver/openbao-ha.env
set +a
deploy/openbao/start-ha.sh
```

第一次运行会构建本仓库提供的 Keepalived 镜像，并拉取 HAProxy/Alpine 依赖。离线环境需要提前构建并导入这些镜像。

## 10. 验证 VIP

在两台代理机分别执行：

```bash
ip address show ens160 | grep 10.0.0.20
docker ps --format 'table {{.Names}}\t{{.Status}}'
```

正常情况下只有一台代理机持有 `10.0.0.20`。然后从 JumpServer 主机验证：

```bash
curl -i http://10.0.0.20:8200/v1/sys/health
```

必须得到 HTTP `200`。HAProxy 将 HTTP `200` 识别为当前 Leader，Standby 返回的 HTTP `429` 不会接收业务流量。

## 11. 配置 JumpServer Core

编辑 JumpServer installer 的 `/opt/jumpserver/config/config.txt`：

```ini
VAULT_ENABLED=true
VAULT_BACKEND=openbao
VAULT_OPENBAO_ADDR=http://10.0.0.20:8200
VAULT_OPENBAO_TOKEN=REPLACE_WITH_SAME_SERVICE_TOKEN
VAULT_OPENBAO_MOUNT_POINT=pam
VAULT_OPENBAO_TIMEOUT=10
OPENBAO_EXTERNAL=true
```

这里必须填写 VIP，不能填写某一台 OpenBao 地址，也不能填写只在单个 Compose 网络中有效的 `openbao` 服务名。

`OPENBAO_EXTERNAL=true` 表示使用外部 OpenBao 集群。Installer 不会启动内置的 `openbao/openbao-init`
服务，也不会拉取内置 OpenBao 镜像；Core 仍会从 `config.txt` 读取上面的 Vault 地址和 Token。

```bash
cd /opt/jumpserver-installer
./jmsctl.sh start
```

验证 Core 容器可以访问 VIP：

```bash
docker exec jms_core python -c \
  'import requests; print(requests.get("http://10.0.0.20:8200/v1/sys/health", timeout=5).status_code)'
```

输出必须是 `200`。随后在 JumpServer 页面保存或更新一个使用 Vault 存储的账号密码，确认业务写入成功。

## 12. 故障切换验证

### OpenBao Leader 故障

先通过 `bao operator raft list-peers` 确认当前 Leader，然后在对应主机停止它：

```bash
docker stop jms-openbao
```

等待 Raft 完成选主后验证：

```bash
curl -i http://10.0.0.20:8200/v1/sys/health
```

返回 HTTP `200` 后，再在 JumpServer 保存一次密码。切换窗口内可能有短暂失败，重新提交即可。

### HAProxy 主机故障

在当前持有 VIP 的代理机停止 HAProxy：

```bash
docker stop jms-openbao-haproxy
```

Keepalived 连续检查失败后，VIP 应漂移到另一台代理机。再次执行：

```bash
curl -i http://10.0.0.20:8200/v1/sys/health
```

测试结束后恢复：

```bash
docker start jms-openbao-haproxy
```

三节点 Raft 只能容忍一台节点故障；同时失去两台节点后没有多数派，密码读写将不可用。
