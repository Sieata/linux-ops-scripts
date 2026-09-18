# linux-ops-scripts

服务器运维脚本合集，方便在多台节点上直接 `git clone` / `git pull` 获取最新版本，
不用每次手动上传文件。

## 脚本

- `fix-logs.sh <目录>` — 通用日志膨胀清理：清空指定目录下超过阈值的 `*.log`，并安装 logrotate 规则防止再次涨爆。适用于任何不会自动轮转日志的常驻服务（代理、网关等）。
- `disk-check.sh` — 检查磁盘/日志维护相关配置（journald 限额、logrotate、定时清理任务），可选执行清理。

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
