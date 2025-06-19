项目介绍
=======
* 脚本根据配置生成用于自动安装的 ubuntu server ISO文件.
* 原项目地址：https://github.com/YasuhiroABE/ub-autoinstall-iso
* 克隆日期：2025-6-17
* 更新时间：2025-6-19


使用方法
====================

安装依赖包.

    $ sudo apt update
    $ sudo apt install git make sudo

检查对应的仓库版本.

    $ sudo git checkout refs/tags/24.04.2 -b my_24.04.2

要下载ISO映像并填充初始文件（以下任务仅执行一次）.

    $ make download
    $ make init

每次生成都需要执行;

    $ make setup
    $ make geniso

生成ISO时，可能因为locale设置而失败, 可以通过指定 LANG=C.

在Makefile文件中修改 `GENISO_LANG` 值.

config/user-data file
---------------------

启动配置文件在 `config/user-data`.

* `config/user-data.efi` - 配置和创建 `UEFI boot` 创建`ESP`区域
* `config/user-data.mbr` - 配置 MBR (BIOS) boot (如果UEFI失败就尝试BIOS)

自动安装的配置放在 `config/user-data`.

The `config/user-data.efi` file is linked as `config/user-data` as the default setting.

如果系统不支持 EFI boot, 可以使用 `config/user-data.mbr`, instead.

另外还支持GRUB，参照原文档.

------------------------------



默认用户密码
---------------------

根据需要更改 `user-data` 中的 `username`和`password`.


* ID: acap
* Password: secret
* （注意，即使不使用密码，仍然需要配置Password，否则会出错）

生成对应 `secret`字符的hash.

    $ openssl passwd -6 -salt "$(openssl rand -hex 8)" secret

其他设置
==============

sudoers文件被安排用于 Ansible
-------------------------------------------------

这包括一个 `sudoers` 文件，该文件已被设置为用户 `acap` 不需要密码.

如果您想更改此设置，请编辑 `config/extras/acap.sudoers` .

SSH keys
--------

下面是一个为默认用户 `acap` 提供 ssh 密钥的例子.

    ssh:
      authorized-keys:
        - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAAIH8mvfUPhRddvGXBxGcvwo5m3CRVOf8RbFXwaUa9mhLX comment"
        - "..."




History
=======

* 2025/03/21
  * Updated the base ISO image filename.

* 2024/04/26
  * Support the Ubuntu 24.04 Desktop and Server versions now.
  * Changed the github repository name to ub-autoinstall-iso

* 2025/06/19
  * 增加了官方sha256的校验
  * 增加了一些其他的辅助方法如设置代理等


其他未翻译，参照REAEME.md