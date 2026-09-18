#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# 通用磁盘/日志维护检查工具。
# 默认只做检查，不改系统配置。
# 传 --clean 时执行一次日志清理：
# - journalctl --vacuum-size=300M
# - truncate 常见文本日志（不含审计类日志）
# - 删除 7 天前 messages-* 轮转
# 再传 --clean-audit-logs 时，额外清空 /var/log/secure、/var/log/cron
# （审计日志，默认不清，避免丢失可追溯性）
# 并输出清理前后对比。
#
# === 用法 ===
# 用法: sudo bash ./disk-check.sh [--clean] [--clean-audit-logs]
#
#   （无参数）           仅检查配置与容量，不做任何改动
#   --clean              检查 + 清理常规日志（不含 secure/cron）
#   --clean-audit-logs   连同 --clean 一起，额外清空审计日志（secure/cron）
#
# === 操作步骤 ===
# 1. 进入本仓库目录（或直接 git clone 到节点上任意目录）
# 2. 仅检查：      sudo bash ./disk-check.sh
# 3. 检查 + 清理： sudo bash ./disk-check.sh --clean
# 4. 连审计日志一起清：sudo bash ./disk-check.sh --clean --clean-audit-logs

JOURNAL_CONF="/etc/systemd/journald.conf.d/size.conf"
LOGROTATE_CONF="/etc/logrotate.d/messages-local"
RUN_CLEAN=0
RUN_CLEAN_AUDIT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean) RUN_CLEAN=1; shift ;;
    --clean-audit-logs) RUN_CLEAN=1; RUN_CLEAN_AUDIT=1; shift ;;
    *)
      echo "未知参数: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$RUN_CLEAN" -eq 1 && "$EUID" -ne 0 ]]; then
  echo "[FAIL] --clean 需要 root 权限运行（请用 sudo），否则部分文件无法截断" >&2
  exit 1
fi

pass() { echo "[PASS] $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[FAIL] $*"; }

echo "=== 磁盘维护配置检查 ==="
echo

echo "1) 检查 journald 限额配置"
if [[ -f "$JOURNAL_CONF" ]]; then
  pass "存在: $JOURNAL_CONF"
  grep -E "SystemMaxUse|RuntimeMaxUse|SystemMaxFileSize|MaxRetentionSec" "$JOURNAL_CONF" || true
else
  fail "缺失: $JOURNAL_CONF"
fi
echo

echo "2) 检查 logrotate messages 规则"
if [[ -f "$LOGROTATE_CONF" ]]; then
  pass "存在: $LOGROTATE_CONF"
  grep -E "rotate|daily|compress|delaycompress|create" "$LOGROTATE_CONF" || true
else
  fail "缺失: $LOGROTATE_CONF"
fi
echo

echo "3) 当前容量与日志占用概览"
df -h /
echo
journalctl --disk-usage || true
echo
du -xhd1 /var/log 2>/dev/null | sort -h || true
echo

if [[ "$RUN_CLEAN" -eq 1 ]]; then
  echo "4) 执行日志清理 (--clean)"
  echo "清理前："
  df -h /
  journalctl --disk-usage || true
  echo

  journalctl --vacuum-size=300M || true

  truncate -s 0 /var/log/messages 2>/dev/null || true
  truncate -s 0 /var/log/maillog 2>/dev/null || true
  truncate -s 0 /var/log/dmesg 2>/dev/null || true
  for f in /var/log/*.log /var/log/*/*.log; do
    truncate -s 0 "$f" 2>/dev/null || true
  done
  find /var/log -maxdepth 1 -type f -name "messages-*" -mtime +7 -delete || true

  if [[ "$RUN_CLEAN_AUDIT" -eq 1 ]]; then
    echo "清空审计日志 (--clean-audit-logs)："
    truncate -s 0 /var/log/secure 2>/dev/null || true
    truncate -s 0 /var/log/cron 2>/dev/null || true
  else
    echo "跳过审计日志 (/var/log/secure, /var/log/cron)，如需清理请加 --clean-audit-logs"
  fi

  echo
  echo "清理后："
  df -h /
  journalctl --disk-usage || true
  du -xhd1 /var/log 2>/dev/null | sort -h || true
  echo
fi

echo "=== 检查完成 ==="
