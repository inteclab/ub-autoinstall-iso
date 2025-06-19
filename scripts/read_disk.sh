#!/bin/bash
echo "=== 磁盘信息总览 ==="
lsblk -o NAME,SIZE,MODEL,SERIAL,WWN

echo -e "\n=== 详细 NVMe 设备信息 ==="
for dev in /dev/nvme*n[0-9]*; do
    if [ -b "$dev" ]; then
        echo "设备: $dev"
        echo "  序列号: $(udevadm info --query=property --name="$dev" | grep ID_SERIAL_SHORT | cut -d= -f2)"
        echo "  WWN: $(udevadm info --query=property --name="$dev" | grep ID_WWN | cut -d= -f2)"
        echo "  型号: $(udevadm info --query=property --name="$dev" | grep ID_MODEL | cut -d= -f2)"
        echo "  厂商: $(udevadm info --query=property --name="$dev" | grep ID_VENDOR | cut -d= -f2)"
        echo "  大小: $(lsblk -dn -o SIZE "$dev")"
        echo "---"
    fi
done