# linux-ops-scripts

服务器运维脚本合集，方便在多台节点上直接 `git clone` / `git pull` 获取最新版本，
不用每次手动上传文件。

## 脚本

- `fix-logs.sh <目录>` — 通用日志膨胀清理：清空指定目录下超过阈值的 `*.log`，并安装 logrotate 规则防止再次涨爆。适用于任何不会自动轮转日志的常驻服务（代理、网关等）。
- `disk-check.sh` — 检查磁盘/日志维护相关配置（journald 限额、logrotate 规则、容量占用），可选执行清理。已兼容 RHEL 系（CentOS/AlmaLinux/Rocky）和 Debian 系（Debian/Ubuntu），会自动探测 `messages`/`syslog`、`maillog`/`mail.log`、`secure`/`auth.log` 用哪个。

两个脚本都只依赖 bash + coreutils（`stat`/`truncate`/`find` 等），在 Debian/Ubuntu 上如果没有 `git`，先装一下：

```bash
apt update && apt install -y git
```

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

# 检查 + 清理常规日志（不含认证/计划任务日志）
sudo bash ./disk-check.sh --clean

# 连认证/计划任务日志一起清（RHEL 系是 secure/cron，Debian 系是 auth.log/cron.log，脚本会自动探测）
sudo bash ./disk-check.sh --clean --clean-audit-logs
```

## 验证 logrotate 规则是否生效

跑完 `fix-logs.sh` 之后，用下面几步确认对应目录的 logrotate 规则确实装对了：

```bash
# 1. 看规则文件内容对不对（路径、size、rotate 份数）
cat /etc/logrotate.d/logfix-etc-v2ray-agent-xray

# 2. debug 模式：只打印会做什么，不会真的轮转、不会改任何文件
logrotate -d /etc/logrotate.d/logfix-etc-v2ray-agent-xray
```

正常情况下 `logrotate -d` 会输出类似：

```
reading config file /etc/logrotate.d/logfix-etc-v2ray-agent-xray
Handling 1 logs

rotating pattern: /etc/v2ray-agent/xray/*.log  209715200 bytes (5 rotations)
empty log files are not rotated, old logs are removed
considering log /etc/v2ray-agent/xray/error.log
  log does not need rotating (log size is below the 'size' threshold)
```

重点看两点：
- `209715200 bytes (5 rotations)` —— 换算下来是 200M / 5 份，跟脚本里写的一致就说明规则没写错。
- 全程没有 `error:` 字样。

如果日志文件当前大小没到阈值，会提示 `log does not need rotating`，这是正常的，不代表规则没生效——只是还没到轮转的时候。以后交给系统的 logrotate 定时任务（`logrotate.timer` 或 `/etc/cron.daily/logrotate`）自动执行即可，不需要手动干预。

某个子目录（比如 `tls`）没有生成对应的规则文件，通常是因为那台机器的 `/etc/v2ray-agent` 下本来就没有那个子目录或没有 `*.log` 文件——`fix-logs.sh` 只会给实际发现日志的目录建规则，属于正常现象。
