#!/usr/bin/env bash

# 日志函数
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    local log_file="${2:-$LOG_FILE}"  # 如果没传第二个参数，就用默认的 LOG_FILE
    echo -e "$message" | sudo tee -a "${LOG_PATH}/${log_file}"  # 注意这里改用 log_file 变量
}

# 错误处理函数
handle_error() {
    local message="$1"
    local log_file="${2:-error.log}"  # 如果没传第二个参数，默认用 error.log
    log "错误: $message" "$log_file"
    exit 1
}

# 只加载一次
if [ -n "$COMMON_LOADED" ]; then
    return 0
fi
export COMMON_LOADED=1

# 设置日志文件
export LOG_PATH="/var/log/lab/pine_script"
sudo mkdir -p "${LOG_PATH}"
export LOG_FILE="pine_script.log"
export APT_FILE="apt.log"

# 检查是否需要 root 权限
CHECK_ROOT=${1:-"yes"}  # 如果没有传参数，默认需要检查 root 权限

if [ "$CHECK_ROOT" = "yes" ]; then
    # 检查是否为 root 用户运行
    if [ "$(id -u)" != "0" ]; then
        handle_error "此脚本必须以 root 权限运行"
    fi
fi