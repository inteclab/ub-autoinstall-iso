<!-- 
记录人：hans
email: han.shaohui@astrocapital.net
更新时间：2025.06.19 
-->

# RAID-6 Setup Documentation

## Overview
* 本文档用来记录基于当前模式下，使用的storage布局。
* 目前使用的是 1 + 10  结构，
* 其中1，作为系统盘，我们使用指定硬盘顺序`/dev/nvme0n1`的方式，防止因为识别错误导致破坏了RAID
	* 注意，增减硬盘可能会影响已有的硬盘顺序
	* 不同系统下的识别可能不一致
* 10，对应其他10个4T硬盘，用来组件RAID6，存储相关数据。
* 由于autoinstall无法实现自动加载已有RAID的原因，我们选择在ISO中只进行系统盘配置。
	Raid6,由系统安装后的其他脚本来实现加载或新建流程。

## Configuration
- Minimum disks: 4 (recommended: 6+)
- Our setup: 10 disks * 4T in RAID-6 array
- Device: /dev/md0
- Volume group: vg0 (LVM on RAID)

## Storage Layout
```
/dev/nvme0n1 (系统盘)
├── efi-partition (1GB)     -> /boot/efi (fat32)
├── boot-partition (2GB)    -> /boot (ext4)  
└── root-partition (剩余)   -> / (ext4)
/dev/md0 (RAID-6，对应其余10块硬盘)   -> LVM Physical Volume 
└── data (全部约32T)   -> /mnt/raid1 (ext4)
```

## RAID建立方法 scripts/setup_raid.sh
```bash
第一次安装，直接无参数运行即可，但如果是非全新硬盘，需要人工确认是否使用了所有可用硬盘。（存在系统引导的硬盘，会被判定为不可用）。

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
```

## Maintenance
- Regular monitoring of disk health
- Backup strategy implementation
- Performance tuning as needed 