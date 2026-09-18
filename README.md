# linux-ops-scripts

服务器运维脚本合集，方便在多台节点上直接 `git clone` / `git pull` 获取最新版本，
不用每次手动上传文件。

## 脚本

- `fix-logs.sh <目录>` — 通用日志膨胀清理：清空指定目录下超过阈值的 `*.log`，并安装 logrotate 规则防止再次涨爆。适用于任何不会自动轮转日志的常驻服务（代理、网关等）。
- `disk-check.sh` — 检查磁盘/日志维护相关配置（journald 限额、logrotate 规则、容量占用），可选执行清理。

## 用法

首次部署到节点：

```bash
git clone https://github.com/Sieata/linux-ops-scripts.git
cd linux-ops-scripts
```

以后更新脚本，节点上执行：

```bash
cd linux-ops-scripts
git pull
```

具体每个脚本的参数说明见脚本文件头部注释。

## 用法示例

### fix-logs.sh — 清理指定目录下的日志膨胀

```bash
# 先 dry-run 看看会清理什么、不做任何改动
sudo bash ./fix-logs.sh /etc/v2ray-agent --dry-run

# 确认没问题后正式清理（默认阈值 100M，超过才清空）
sudo bash ./fix-logs.sh /etc/v2ray-agent

# 换一个更低的阈值，或者扫描别的服务的日志目录
sudo bash ./fix-logs.sh /var/log/myapp --threshold 50
```

示例输出：

```
=== 日志膨胀检查/清理 ===
扫描目录: /etc/v2ray-agent

1) 扫描日志文件（阈值 100M）
[PASS] 已清空: /etc/v2ray-agent/xray/access.log (释放 12G)
[INFO] 未超阈值，跳过: /etc/v2ray-agent/xray/error.log (3.2M)

2) 安装 logrotate 规则，防止再次涨爆
[PASS] 已写入: /etc/logrotate.d/logfix-etc-v2ray-agent-xray

3) 当前磁盘占用
...
共释放约: 12.1GB
=== 处理完成 ===
```

### disk-check.sh — 检查磁盘/日志维护配置

```bash
# 仅检查，不改任何东西
sudo bash ./disk-check.sh

# 检查 + 清理常规日志（不含 secure/cron）
sudo bash ./disk-check.sh --clean

# 连审计日志（/var/log/secure、/var/log/cron）一起清
sudo bash ./disk-check.sh --clean --clean-audit-logs
```
