#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"  # 脚本所在目录

. ${SCRIPT_DIR}/common.sh

# 默认配置 - 将在运行时自动检测可用磁盘
DISKS=()
MOUNT_POINT="/mnt/raid"
RAID_DEVICE="/dev/md0"
RAID_LEVEL="6"  # 默认RAID级别

# 自动检测可用磁盘
detect_available_disks() {
    local available_disks=()
    
    # 处理 NVMe 设备
    for dev in /dev/nvme*n[0-9]*; do
        if [ -b "$dev" ]; then
            # 检查是否为系统盘 - 更严格的检查
            local is_system_disk=false
            
            # 检查是否有分区挂载到系统目录
            for part in ${dev}p*; do
                if [ -b "$part" ]; then
                    if mount | grep -q "^$part.* / " || mount | grep -q "^$part.* /boot"; then
                        is_system_disk=true
                        break
                    fi
                fi
            done
            
            # 也检查整个磁盘是否被挂载
            if mount | grep -q "^$dev.* / " || mount | grep -q "^$dev.* /boot"; then
                is_system_disk=true
            fi
            
            # 如果不是系统盘且没有被挂载，则添加到可用列表
            if [ "$is_system_disk" = false ]; then
                # 检查是否已被挂载到其他位置
                if ! mount | grep -q "^$dev"; then
                    # 检查分区是否被挂载
                    local has_mounted_partition=false
                    for part in ${dev}p*; do
                        if [ -b "$part" ] && mount | grep -q "^$part"; then
                            has_mounted_partition=true
                            break
                        fi
                    done
                    
                    if [ "$has_mounted_partition" = false ]; then
                        available_disks+=("$dev")
                    fi
                fi
            fi
        fi
    done

    # 处理 SATA 设备
    for letter in {a..z}; do
        dev="/dev/sd$letter"
        if [ -b "$dev" ]; then
            # 检查是否为系统盘
            local is_system_disk=false
            
            # 检查分区是否挂载到系统目录
            for i in $(seq 1 9); do
                part="${dev}${i}"
                if [ -b "$part" ]; then
                    if mount | grep -q "^$part.* / " || mount | grep -q "^$part.* /boot"; then
                        is_system_disk=true
                        break
                    fi
                fi
            done
            
            # 也检查整个磁盘是否被挂载
            if mount | grep -q "^$dev.* / " || mount | grep -q "^$dev.* /boot"; then
                is_system_disk=true
            fi
            
            # 如果不是系统盘且没有被挂载，则添加到可用列表
            if [ "$is_system_disk" = false ]; then
                # 检查是否已被挂载到其他位置
                if ! mount | grep -q "^$dev"; then
                    # 检查分区是否被挂载
                    local has_mounted_partition=false
                    for i in $(seq 1 9); do
                        part="${dev}${i}"
                        if [ -b "$part" ] && mount | grep -q "^$part"; then
                            has_mounted_partition=true
                            break
                        fi
                    done
                    
                    if [ "$has_mounted_partition" = false ]; then
                        available_disks+=("$dev")
                    fi
                fi
            fi
        fi
    done

    echo "${available_disks[@]}"
}

# 验证RAID级别和磁盘数量
validate_raid_config() {
    local level=$1
    local disk_count=$2
    
    case $level in
        1)
            if [ $disk_count -lt 2 ]; then
                handle_error "RAID 1 至少需要 2 个磁盘，当前只有 $disk_count 个"
            fi
            ;;
        5)
            if [ $disk_count -lt 3 ]; then
                handle_error "RAID 5 至少需要 3 个磁盘，当前只有 $disk_count 个"
            fi
            ;;
        6)
            if [ $disk_count -lt 4 ]; then
                handle_error "RAID 6 至少需要 4 个磁盘，当前只有 $disk_count 个"
            fi
            ;;
        10)
            if [ $disk_count -lt 4 ] || [ $((disk_count % 2)) -ne 0 ]; then
                handle_error "RAID 10 至少需要 4 个磁盘且必须为偶数，当前有 $disk_count 个"
            fi
            ;;
        *)
            handle_error "不支持的RAID级别: $level。支持的级别: 1, 5, 6, 10"
            ;;
    esac
}

# 回滚函数
rollback() {
    log "开始回滚操作..."
    mdadm --stop "$RAID_DEVICE" 2>/dev/null
    sed -i "\|UUID=.*$MOUNT_POINT|d" /etc/fstab
    umount "$MOUNT_POINT" 2>/dev/null
    log "回滚完成"
}

show_help() {
    echo "当前系统中的硬盘："
    # 显示所有磁盘设备
    lsblk -d -o NAME,SIZE,MODEL | grep -E 'nvme|sd'

    echo -e "\n系统磁盘分析："
    # 显示系统盘信息
    echo "系统盘:"
    mount | grep -E " / | /boot" | while read line; do
        dev=$(echo "$line" | cut -d' ' -f1)
        mount_point=$(echo "$line" | awk '{print $3}')
        echo "  $dev -> $mount_point"
    done

    echo -e "\n可用的硬盘设备：(仅展示非系统硬盘的磁盘)"
    
    local available_disks=($(detect_available_disks))
    if [ ${#available_disks[@]} -eq 0 ]; then
        echo "  未找到可用磁盘"
    else
        for disk in "${available_disks[@]}"; do
            echo "  $disk ($(lsblk -dn -o SIZE,MODEL "$disk" 2>/dev/null || echo "信息不可用"))"
        done
    fi

    echo -e "\n用法: $(basename "$0") [选项] [磁盘列表] [挂载点]"
    cat <<EOF
参数说明:
    无参数              使用默认配置 (所有可用磁盘, RAID级别: $RAID_LEVEL, 挂载点: $MOUNT_POINT)
    -l, --level LEVEL   指定RAID级别 (1, 5, 6, 10)
    磁盘1 磁盘2 ...     指定磁盘设备列表
    
选项:
    -h, --help          显示帮助信息
    -l, --level LEVEL   指定RAID级别 (1, 5, 6, 10)，默认为 5

RAID级别说明:
    RAID 1: 镜像，至少需要2个磁盘，提供冗余但不提供容量扩展
    RAID 5: 分布式奇偶校验，至少需要3个磁盘，提供冗余和容量扩展
    RAID 6: 双重分布式奇偶校验，至少需要4个磁盘，可承受2个磁盘故障
    RAID 10: 镜像+条带，至少需要4个磁盘(偶数)，高性能和冗余

示例:
    $(basename "$0")                                    # 使用所有可用磁盘创建RAID5
    $(basename "$0") -l 1                               # 使用所有可用磁盘创建RAID1
    $(basename "$0") -l 6 /dev/nvme0n1 /dev/nvme0n2 /dev/nvme0n3 /dev/nvme0n4    # 指定磁盘创建RAID6
    $(basename "$0") /dev/nvme0n1 /dev/nvme0n2 /dev/nvme0n3 /mnt/my_raid         # 指定磁盘和挂载点
EOF
    exit 2
}

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    handle_error "请使用root权限运行此脚本"
fi

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -l|--level)
            if [ -z "$2" ]; then
                handle_error "选项 -l/--level 需要指定RAID级别"
            fi
            RAID_LEVEL="$2"
            shift 2
            ;;
        -*)
            handle_error "未知选项: $1"
            ;;
        *)
            break
            ;;
    esac
done

# 处理剩余参数
if [ $# -eq 0 ]; then
    # 没有参数，使用默认配置
    DISKS=($(detect_available_disks))
    if [ ${#DISKS[@]} -eq 0 ]; then
        echo "错误：未找到可用的磁盘设备"
        echo ""
        echo "调试信息："
        echo "系统挂载情况："
        mount | grep -E "nvme|sd" | head -10
        echo ""
        echo "磁盘设备："
        ls -la /dev/nvme* 2>/dev/null | head -10
        echo ""
        show_help
    fi
    log "使用默认配置: RAID级别=$RAID_LEVEL, 磁盘=[${DISKS[*]}], 挂载点=$MOUNT_POINT"
elif [ $# -eq 1 ] && [ -d "$1" -o "${1:0:1}" = "/" ]; then
    # 单个参数且看起来像路径，作为挂载点
    MOUNT_POINT="$1"
    DISKS=($(detect_available_disks))
    if [ ${#DISKS[@]} -eq 0 ]; then
        handle_error "未找到可用的磁盘设备"
    fi
    log "使用指定挂载点: RAID级别=$RAID_LEVEL, 磁盘=[${DISKS[*]}], 挂载点=$MOUNT_POINT"
else
    # 多个参数，最后一个可能是挂载点
    if [ "${!#:0:1}" = "/" ] && [ ! -b "${!#}" ]; then
        # 最后一个参数看起来像路径且不是块设备，作为挂载点
        MOUNT_POINT="${!#}"
        DISKS=("${@:1:$#-1}")
    else
        # 所有参数都是磁盘
        DISKS=("$@")
    fi
    log "使用指定配置: RAID级别=$RAID_LEVEL, 磁盘=[${DISKS[*]}], 挂载点=$MOUNT_POINT"
fi

# 验证RAID配置
validate_raid_config "$RAID_LEVEL" "${#DISKS[@]}"

check_existing_raid() {
    log "扫描现有 RAID 配置..."
    local has_raid=false
    local raid_uuid=""
    local found_disks=()

    # 首先检查是否已经有活动的RAID设备
    if [ -b "$RAID_DEVICE" ]; then
        if mdadm --detail "$RAID_DEVICE" &>/dev/null; then
            local raid_status=$(mdadm --detail "$RAID_DEVICE" | grep "State :" | awk '{print $3}')
            local current_level=$(mdadm --detail "$RAID_DEVICE" | grep "Raid Level" | awk '{print $4}')
            log "检测到活动的RAID设备 $RAID_DEVICE，级别: RAID$current_level，状态: $raid_status"

            # 检查文件系统和挂载情况
            if ! blkid "$RAID_DEVICE" &>/dev/null; then
                log "RAID设备存在但没有文件系统，创建文件系统..."
                mkfs.ext4 "$RAID_DEVICE" || handle_error "创建文件系统失败"
            fi

            # 检查并创建挂载点
            if [ ! -d "$MOUNT_POINT" ]; then
                log "创建挂载点 $MOUNT_POINT"
                mkdir -p "$MOUNT_POINT" || handle_error "创建挂载点失败"
            fi

            # 检查并更新fstab
            if ! grep -q "$MOUNT_POINT" /etc/fstab; then
                log "添加RAID设备到fstab..."
                local UUID=$(blkid -s UUID -o value "$RAID_DEVICE")
                echo "UUID=$UUID $MOUNT_POINT ext4 defaults 0 0" >>/etc/fstab ||
                    handle_error "更新fstab失败"
                systemctl daemon-reload
            fi

            # 检查并挂载
            if ! mount | grep -q "$RAID_DEVICE on $MOUNT_POINT"; then
                log "挂载RAID设备..."
                mount "$MOUNT_POINT" || handle_error "挂载RAID设备失败"
            fi

            return 0
        fi
    fi

    # 检查磁盘上是否存在RAID配置
    for disk in "${DISKS[@]}"; do
        if mdadm --examine "$disk" &>/dev/null; then
            local disk_role=$(mdadm --examine "$disk" | grep "Device Role" | awk '{print $4}')
            local disk_uuid=$(mdadm --examine "$disk" | grep "Array UUID" | awk '{print $4}')
            local array_level=$(mdadm --examine "$disk" | grep "Raid Level" | awk '{print $4}')

            found_disks+=("$disk")

            if [[ -n "$raid_uuid" && "$disk_uuid" != "$raid_uuid" ]]; then
                handle_error "错误：检测到磁盘属于不同的RAID阵列, 磁盘 ${found_disks[*]} 不能一起使用"
            fi

            raid_uuid="$disk_uuid"
            has_raid=true

            log "发现磁盘 $disk 属于RAID$array_level 阵列 ($raid_uuid)"
        fi
    done

    if $has_raid; then
        log "发现现有RAID配置，尝试组装..."

        # 如果RAID设备已存在但状态不正常，先停止它
        if [ -b "$RAID_DEVICE" ]; then
            log "停止现有RAID设备..."
            mdadm --stop "$RAID_DEVICE"
        fi

        # 组装RAID
        if mdadm --assemble "$RAID_DEVICE" "${found_disks[@]}"; then
            log "成功组装RAID设备 $RAID_DEVICE"

            # 确保文件系统存在
            if ! blkid "$RAID_DEVICE" &>/dev/null; then
                log "创建文件系统..."
                mkfs.ext4 "$RAID_DEVICE" || handle_error "创建文件系统失败"
            fi

            # 检查并创建挂载点
            if [ ! -d "$MOUNT_POINT" ]; then
                log "创建挂载点 $MOUNT_POINT"
                mkdir -p "$MOUNT_POINT" || handle_error "创建挂载点失败"
            fi

            # 检查并更新fstab
            if ! grep -q "$MOUNT_POINT" /etc/fstab; then
                log "添加RAID设备到fstab..."
                local UUID=$(blkid -s UUID -o value "$RAID_DEVICE")
                echo "UUID=$UUID $MOUNT_POINT ext4 defaults 0 0" >>/etc/fstab ||
                    handle_error "更新fstab失败"
                systemctl daemon-reload
            fi

            # 挂载设备
            if ! mount | grep -q "$RAID_DEVICE on $MOUNT_POINT"; then
                log "挂载RAID设备..."
                mount "$MOUNT_POINT" || handle_error "挂载RAID设备失败"
            fi

            return 0
        else
            mdadm --detail "$RAID_DEVICE" 2>&1 | while IFS= read -r line; do
                log "  $line"
            done
            handle_error "组装RAID设备失败"
        fi
    fi

    log "未发现现有RAID配置，可以继续创建新的RAID$RAID_LEVEL"
    return 1
}

# 磁盘检查
check_disks() {
    log "检查磁盘设备..."

    for DISK in "${DISKS[@]}"; do
        # 检查设备是否存在
        if [ ! -b "$DISK" ]; then
            handle_error "找不到磁盘 $DISK"
        fi

        # 检查是否被挂载
        if mount | grep -q "^$DISK"; then
            handle_error "错误：$DISK 已被挂载，请先卸载"
        fi

        # 检查分区是否被挂载
        for part in ${DISK}p*; do
            if [ -b "$part" ] && mount | grep -q "^$part"; then
                handle_error "错误：$DISK 的分区 $part 当前正在使用中"
            fi
        done

        # 检查是否为系统盘
        for part in ${DISK}p*; do
            if [ -b "$part" ]; then
                if mount | grep -q "^$part.* / " || mount | grep -q "^$part.* /boot"; then
                    handle_error "错误：$DISK 包含系统分区，不能用于RAID"
                fi
            fi
        done
    done

    # 显示分区信息和确认
    echo "检测到以下磁盘的分区表："
    for DISK in "${DISKS[@]}"; do
        echo "磁盘 $DISK："
        if fdisk -l "$DISK" 2>/dev/null | grep -q "Disk label type:"; then
            fdisk -l "$DISK" 2>/dev/null | grep -E "Disk|Device|Type"
        else
            echo "  无分区表或无法读取"
        fi
        echo ""
    done

    # 最后确认
    echo -e "\n将要使用以下磁盘创建RAID$RAID_LEVEL："
    for i in "${!DISKS[@]}"; do
        echo "磁盘$((i+1)): ${DISKS[i]} ($(lsblk -dn -o SIZE,MODEL "${DISKS[i]}" 2>/dev/null || echo "信息不可用"))"
    done
    echo "挂载点: $MOUNT_POINT"
    
    read -p "确认继续？这将清除这些磁盘上的所有数据 (yes/no) " final_confirm
    if [ "$final_confirm" != "yes" ]; then
        handle_error "用户取消操作"
    fi

    # 清除分区表
    for DISK in "${DISKS[@]}"; do
        log "清除 $DISK 的分区表"
        sgdisk --zap-all "$DISK" 2>/dev/null || {
            log "sgdisk 失败，尝试使用 wipefs"
            wipefs -a "$DISK" || handle_error "清除分区表失败"
        }
    done

    log "磁盘检查完成"
}

# 检查挂载点
check_mount_point() {
    log "检查挂载点 $MOUNT_POINT..."

    # 检查挂载点是否已经存在且不为空
    if [ -d "$MOUNT_POINT" ]; then
        if [ "$(ls -A "$MOUNT_POINT")" ]; then
            handle_error "挂载点 $MOUNT_POINT 不为空，请先清空或指定其他挂载点"
        fi
    fi

    # 检查挂载点是否已经被其他设备使用
    if mount | grep -q " on $MOUNT_POINT "; then
        handle_error "挂载点 $MOUNT_POINT 已被其他设备使用"
    fi

    # 检查挂载点是否在 fstab 中已有配置
    if grep -q "$MOUNT_POINT" /etc/fstab; then
        handle_error "挂载点 $MOUNT_POINT 在 /etc/fstab 中已有配置"
    fi

    # 检查挂载点路径的父目录是否存在且有写权限
    parent_dir=$(dirname "$MOUNT_POINT")
    if [ ! -w "$parent_dir" ]; then
        handle_error "没有权限创建挂载点，请检查 $parent_dir 的权限"
    fi

    log "挂载点检查完成"
}

# 最终检查函数
final_check() {
    log "执行最终检查..."

    # 首先检查RAID设备是否存在
    if [ ! -b "$RAID_DEVICE" ]; then
        handle_error "RAID设备 $RAID_DEVICE 不存在"
    fi

    # 检查RAID状态
    local raid_detail=$(mdadm --detail "$RAID_DEVICE")
    local raid_state=$(echo "$raid_detail" | grep "State :" | awk '{print $3, $4, $5}')
    local raid_level=$(echo "$raid_detail" | grep "Raid Level" | awk '{print $4}')
    local total_devices=$(echo "$raid_detail" | grep "Total Devices" | awk '{print $4}')
    
    log "当前RAID状态: $raid_state"
    log "RAID级别: RAID$raid_level"
    log "设备总数: $total_devices"

    # 检查状态
    case "$raid_state" in
    *"clean"* | *"active"* | *"resyncing"*)
        # 标记是否有特殊情况
        has_special_condition=false

        if [[ "$raid_state" == *"read-only"* ]]; then
            log "警告: RAID当前处于只读状态，请稍后使用 'mdadm --detail $RAID_DEVICE' 确认状态"
            has_special_condition=true
        fi

        if [[ "$raid_state" == *"degraded"* ]]; then
            log "警告: RAID当前处于降级状态，请稍后使用 'mdadm --detail $RAID_DEVICE' 检查具体情况"
            has_special_condition=true
        fi

        if [[ "$raid_state" == *"resyncing"* ]]; then
            log "提示: RAID正在重新同步，请稍后使用 'mdadm --detail $RAID_DEVICE' 确认同步是否完成"
            has_special_condition=true
        fi

        # 如果没有特殊情况，输出正常状态信息
        if [ "$has_special_condition" = false ]; then
            log "RAID状态正常，可以正常使用"
        fi
        ;;
    *)
        handle_error "RAID状态异常: $raid_state"
        ;;
    esac

    # 检查挂载状态
    if ! mount | grep -q "$RAID_DEVICE on $MOUNT_POINT"; then
        handle_error "挂载点检查失败"
    fi

    # 检查文件系统
    if ! df -h "$MOUNT_POINT"; then
        handle_error "文件系统检查失败"
    fi

    log "所有检查通过"

    # 显示最终状态
    echo "RAID $RAID_LEVEL 设置完成！"
    echo "RAID级别: $raid_level"
    echo "设备总数: $total_devices"
    echo "挂载点: $MOUNT_POINT"
    echo "使用的磁盘: ${DISKS[*]}"
    echo "详细日志请查看: $LOG_FILE"
    echo ""
    echo "可用命令："
    echo "  查看RAID状态: mdadm --detail $RAID_DEVICE"
    echo "  查看磁盘使用: df -h $MOUNT_POINT"

    return 0
}

# 主要处理流程
main() {
    # 设置异常回滚
    trap rollback ERR

    # 检查是否存在现有 RAID
    if check_existing_raid; then
        log "现有 RAID 配置正常运行"
        final_check
        return 0
    fi

    # 如果没有现有RAID,继续创建新的RAID
    log "开始创建新的 RAID$RAID_LEVEL 配置..."

    # 检查磁盘
    check_disks

    # 检查挂载点
    check_mount_point

    # 创建挂载点
    log "创建挂载点 $MOUNT_POINT"
    mkdir -p "$MOUNT_POINT" || handle_error "创建挂载点失败"

    # 创建RAID阵列
    log "创建RAID $RAID_LEVEL 阵列..."
    case $RAID_LEVEL in
        1)
            mdadm --create "$RAID_DEVICE" --level=1 --raid-devices=${#DISKS[@]} "${DISKS[@]}" ||
                handle_error "创建RAID 1失败"
            ;;
        5)
            mdadm --create "$RAID_DEVICE" --level=5 --raid-devices=${#DISKS[@]} "${DISKS[@]}" ||
                handle_error "创建RAID 5失败"
            ;;
        6)
            mdadm --create "$RAID_DEVICE" --level=6 --raid-devices=${#DISKS[@]} "${DISKS[@]}" ||
                handle_error "创建RAID 6失败"
            ;;
        10)
            mdadm --create "$RAID_DEVICE" --level=10 --raid-devices=${#DISKS[@]} "${DISKS[@]}" ||
                handle_error "创建RAID 10失败"
            ;;
        *)
            handle_error "不支持的RAID级别: $RAID_LEVEL"
            ;;
    esac

    # 等待RAID设备就绪
    log "等待RAID设备就绪..."
    sleep 5

    # 创建文件系统
    log "等待文件系统准备就绪..."
    sleep 3
    log "创建文件系统..."
    mkfs.ext4 "$RAID_DEVICE" || handle_error "创建文件系统失败"

    # 获取UUID并更新fstab
    UUID=$(blkid -s UUID -o value "$RAID_DEVICE")
    echo "UUID=$UUID $MOUNT_POINT ext4 defaults 0 0" >>/etc/fstab ||
        handle_error "更新fstab失败"

    # 重载系统服务
    log "重载系统服务..."
    systemctl daemon-reload || handle_error "重载系统服务失败"

    # 挂载RAID
    log "挂载RAID..."
    mount "$RAID_DEVICE" "$MOUNT_POINT" || handle_error "挂载失败"

    # 保存RAID配置
    log "保存RAID配置..."
    mkdir -p /etc/mdadm
    mdadm --detail --scan >>/etc/mdadm/mdadm.conf || handle_error "保存RAID配置失败"
    update-initramfs -u || handle_error "更新initramfs失败"

    # 最终检查
    final_check

    # 在main函数结束前清除trap
    trap - ERR
}

main