<!-- 
记录人：hans
email: han.shaohui@astrocapital.net
更新时间：2025.06.19 
-->

# RAID-6 Setup Documentation

## Overview
* 本文档用来记录基于当前模式下，使用的storage布局。
* 目前使用的是 1 + 10  结构，
* 其中1，作为系统盘，我们使用指定序列号的方式，防止因为识别错误导致破坏了RAID
	* `S7DPNF0Y306493W` = prod 当前的系统盘
	* `S7DPNF0XB12344H` = dev 当前的系统盘
	* 增加了vmware硬盘的识别用于测试
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

## Monitoring Commands
```bash
# Check RAID status
cat /proc/mdstat
mdadm --detail /dev/md0

# Check disk health
sudo smartctl -a /dev/sdb
```

## Maintenance
- Regular monitoring of disk health
- Backup strategy implementation
- Performance tuning as needed 