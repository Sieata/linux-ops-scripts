#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# 一键处理 v2ray-agent (xray/v2ray/trojan/hysteria/tuic/sing-box) 日志
# 无限增长吃满磁盘的问题。背景：xray 等默认不会自动轮转 access.log /
# error.log，长期运行后单个日志文件可能涨到几十 G，把系统盘写满。
#
# 本脚本做两件事：
#   1) 找到超过阈值的日志文件并 truncate 清空（进程持有 fd 会继续写同一个
#      inode，磁盘空间立即释放，不需要重启代理服务）
#   2) 给每个发现日志的子目录安装 logrotate 规则（copytruncate，无需给
#      xray 发信号），防止以后再涨爆
#
# === 用法 ===
# 用法: sudo bash ./fix_v2ray_log_bloat.sh [安装目录] [选项]
#
#   （无参数）             默认扫描 /etc/v2ray-agent，清理 + 装 logrotate
#   [安装目录]             v2ray-agent 不是默认路径时，传自定义路径
#   --dry-run              只报告发现了什么，不清理、不写 logrotate 配置
#   --threshold SIZE_MB    超过这个大小（MB）才清理，默认 100
#
# 示例：
#   sudo bash ./fix_v2ray_log_bloat.sh
#   sudo bash ./fix_v2ray_log_bloat.sh --dry-run
#   sudo bash ./fix_v2ray_log_bloat.sh /opt/v2ray-agent --threshold 50

BASE_DIR="/etc/v2ray-agent"
DRY_RUN=0
THRESHOLD_MB=100

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --threshold)
      THRESHOLD_MB="${2:?--threshold 需要一个数值参数}"
      shift 2
      ;;
    -*)
      echo "未知选项: $1" >&2
      exit 1
      ;;
    *)
      BASE_DIR="$1"
      shift
      ;;
  esac
done

if [[ "$EUID" -ne 0 ]]; then
  echo "[FAIL] 需要 root 权限运行（请用 sudo）" >&2
  exit 1
fi

pass() { echo "[PASS] $*"; }
info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }

echo "=== v2ray-agent 日志膨胀检查/清理 ==="
echo "安装目录: $BASE_DIR"
[[ "$DRY_RUN" -eq 1 ]] && info "dry-run 模式，只报告不会做任何改动"
echo

if [[ ! -d "$BASE_DIR" ]]; then
  info "未发现 $BASE_DIR，本机可能没装 v2ray-agent，跳过"
  exit 0
fi

THRESHOLD_BYTES=$((THRESHOLD_MB * 1024 * 1024))
TOTAL_FREED=0
DIRS_WITH_LOGS=()

echo "1) 扫描日志文件（阈值 ${THRESHOLD_MB}M）"
while IFS= read -r -d '' logfile; do
  size_bytes=$(stat -c%s "$logfile" 2>/dev/null || echo 0)
  size_human=$(du -h "$logfile" 2>/dev/null | cut -f1)
  logdir=$(dirname "$logfile")

  if [[ "$size_bytes" -ge "$THRESHOLD_BYTES" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      warn "超阈值（会被清空）: $logfile ($size_human)"
    else
      truncate -s 0 "$logfile"
      pass "已清空: $logfile (释放 $size_human)"
      TOTAL_FREED=$((TOTAL_FREED + size_bytes))
    fi
  else
    info "未超阈值，跳过: $logfile ($size_human)"
  fi

  DIRS_WITH_LOGS+=("$logdir")
done < <(find "$BASE_DIR" -type f -name "*.log" -print0 2>/dev/null)

if [[ ${#DIRS_WITH_LOGS[@]} -eq 0 ]]; then
  info "没有找到任何 *.log 文件，无需处理"
  exit 0
fi
echo

echo "2) 安装 logrotate 规则，防止再次涨爆"
mapfile -t UNIQUE_DIRS < <(printf '%s\n' "${DIRS_WITH_LOGS[@]}" | sort -u)
for dir in "${UNIQUE_DIRS[@]}"; do
  conf_name="v2ray-agent-$(basename "$dir")"
  conf_path="/etc/logrotate.d/$conf_name"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "会写入: $conf_path (规则: $dir/*.log)"
    continue
  fi

  cat > "$conf_path" << EOF
$dir/*.log {
    daily
    rotate 5
    size 200M
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF
  pass "已写入: $conf_path"
done
echo

if [[ "$DRY_RUN" -eq 0 ]]; then
  freed_human=$(numfmt --to=iec --suffix=B "$TOTAL_FREED" 2>/dev/null || echo "${TOTAL_FREED}B")
  echo "3) 当前磁盘占用"
  df -h /
  echo
  echo "共释放约: $freed_human"
fi

echo "=== 处理完成 ==="
