SHELL := /bin/bash
ISO_URLBASE = https://releases.ubuntu.com/24.04/
# ISO_FILENAME = ubuntu-24.04.2-desktop-amd64.iso
ISO_FILENAME = ubuntu-24.04.2-live-server-amd64.iso
ISO_MOUNTPOINT = /mnt/iso
ISO_ROOT = iso_root

# SHA256 校验和缓存文件
ISO_SHA256_CACHE = .$(ISO_FILENAME).sha256
ISO_SHA256_URL = $(ISO_URLBASE)/SHA256SUMS

# 代理配置文件
PROXY_CONFIG = .proxy_config

## copy files
GRUBCFG_SRC = config/boot/grub/grub.cfg
GRUBCFG_DEST = iso_root/boot/grub/grub.cfg
USERDATA_SRC = config/user-data
USERDATA_DEST = iso_root/user-data
METADATA_SRC = config/meta-data
METADATA_DEST = iso_root/meta-data
EXTRAS_SRCDIR = config/extras/
EXTRAS_DESTDIR = iso_root/

GENISO_LABEL = MYUBISOIMG
GENISO_FILENAME = ubuntu-custom-autoinstaller.$(shell date +%Y%m%d.%H%M%S).iso
GENISO_BOOTIMG = boot/grub/i386-pc/eltorito.img
GENISO_BOOTCATALOG = /boot.catalog
GENISO_LANG = C
GENISO_START_SECTOR = $(shell sudo env LANG=$(GENISO_LANG) fdisk -l $(ISO_FILENAME) |grep iso2 | cut -d' ' -f2)
GENISO_END_SECTOR = $(shell sudo env LANG=$(GENISO_LANG) fdisk -l $(ISO_FILENAME) |grep iso2 | cut -d' ' -f3)

## for APU/APU2
GENISO_ISOLINUX = /usr/lib/ISOLINUX/isolinux.bin
GENISO_ISOLINUX_MODULEDIR = /usr/lib/syslinux/modules/bios/
GENISO_HYBRIDMBR = /usr/lib/ISOLINUX/isohdpfx.bin
ISOLINUX_CONFIGDIR = config/isolinux
ISOLINUX_DIRNAME = isolinux

# 代理设置
.PHONY: set-proxy
set-proxy:
	@if [ -z "$(PROXY)" ]; then \
		echo "用法: make set-proxy PROXY=<代理地址>"; \
		echo "示例:"; \
		echo "  make set-proxy PROXY=http://127.0.0.1:7890"; \
		echo "  make set-proxy PROXY=socks5://127.0.0.1:1080"; \
		echo "  make set-proxy PROXY=http://user:pass@proxy.example.com:8080"; \
		exit 1; \
	fi
	@echo "设置代理: $(PROXY)"
	@echo "export http_proxy=$(PROXY)" > $(PROXY_CONFIG)
	@echo "export https_proxy=$(PROXY)" >> $(PROXY_CONFIG)
	@echo "export HTTP_PROXY=$(PROXY)" >> $(PROXY_CONFIG)
	@echo "export HTTPS_PROXY=$(PROXY)" >> $(PROXY_CONFIG)
	@echo "export ftp_proxy=$(PROXY)" >> $(PROXY_CONFIG)
	@echo "export FTP_PROXY=$(PROXY)" >> $(PROXY_CONFIG)
	@echo "export no_proxy=localhost,127.0.0.1,::1" >> $(PROXY_CONFIG)
	@echo "export NO_PROXY=localhost,127.0.0.1,::1" >> $(PROXY_CONFIG)
	@echo "✓ 代理配置已保存到 $(PROXY_CONFIG)"
	@echo "当前会话请运行: source $(PROXY_CONFIG)"

# 取消代理
.PHONY: unset-proxy
unset-proxy:
	@echo "取消代理设置..."
	@rm -f $(PROXY_CONFIG)
	@unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ftp_proxy FTP_PROXY no_proxy NO_PROXY 2>/dev/null || true
	@echo "✓ 代理配置已清除"
	@echo "当前会话请运行以下命令清除环境变量:"
	@echo "unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ftp_proxy FTP_PROXY no_proxy NO_PROXY"

# 显示代理状态
.PHONY: proxy-status
proxy-status:
	@echo "=== 代理状态 ==="
	@if [ -f "$(PROXY_CONFIG)" ]; then \
		echo "代理配置文件: 存在"; \
		echo "配置内容:"; \
		cat $(PROXY_CONFIG); \
	else \
		echo "代理配置文件: 不存在"; \
	fi
	@echo ""
	@echo "当前环境变量:"
	@echo "http_proxy: $${http_proxy:-未设置}"
	@echo "https_proxy: $${https_proxy:-未设置}"
	@echo "HTTP_PROXY: $${HTTP_PROXY:-未设置}"
	@echo "HTTPS_PROXY: $${HTTPS_PROXY:-未设置}"

# 使用代理执行命令的辅助函数
define with_proxy
	$(if $(wildcard $(PROXY_CONFIG)), source $(PROXY_CONFIG) && )
endef

# 获取官方 SHA256 值（支持代理）
.PHONY: get-official-sha256
get-official-sha256:
	@if [ ! -f "$(ISO_SHA256_CACHE)" ]; then \
		echo "获取官方 SHA256 校验和 ($(ISO_SHA256_URL))..."; \
		if [ -f "$(PROXY_CONFIG)" ]; then \
			echo "使用代理配置..."; \
			source $(PROXY_CONFIG); \
		fi; \
		echo "尝试下载 SHA256SUMS 文件..."; \
		if command -v curl >/dev/null 2>&1; then \
			echo "使用 curl 下载..."; \
			$(call with_proxy)curl --connect-timeout 10 --max-time 30 -s "$(ISO_SHA256_URL)" | grep "$(ISO_FILENAME)" | cut -d' ' -f1 > $(ISO_SHA256_CACHE) 2>/dev/null; \
		else \
			echo "使用 wget 下载..."; \
			$(call with_proxy)wget --timeout=10 --tries=2 -q -O- "$(ISO_SHA256_URL)" | grep "$(ISO_FILENAME)" | cut -d' ' -f1 > $(ISO_SHA256_CACHE) 2>/dev/null; \
		fi; \
		if [ -s "$(ISO_SHA256_CACHE)" ]; then \
			echo "已缓存 SHA256: $$(cat $(ISO_SHA256_CACHE))"; \
		else \
			echo "错误: 无法获取 $(ISO_FILENAME) 的校验和"; \
			echo "请检查网络连接、代理设置或手动设置 SHA256 值"; \
			rm -f $(ISO_SHA256_CACHE); \
			exit 1; \
		fi; \
	else \
		echo "使用缓存的 SHA256: $$(cat $(ISO_SHA256_CACHE))"; \
	fi

.PHONY: check-download
check-download: get-official-sha256
	@echo "检查下载文件完整性..."
	@if [ ! -f "$(ISO_FILENAME)" ]; then \
		echo "错误: ISO 文件不存在"; \
		exit 1; \
	fi
	@echo "检查文件大小..."
	@ACTUAL_SIZE=$$(stat -c%s "$(ISO_FILENAME)" 2>/dev/null || echo "0"); \
	if [ "$$ACTUAL_SIZE" -lt 1000000000 ]; then \
		echo "错误: 文件大小异常 ($$ACTUAL_SIZE 字节)"; \
		exit 1; \
	fi; \
	echo "文件大小: $$ACTUAL_SIZE 字节"
	@echo "验证 SHA256 校验和..."
	@EXPECTED_SHA256=$$(cat $(ISO_SHA256_CACHE)); \
	ACTUAL_SHA256=$$(sha256sum "$(ISO_FILENAME)" | cut -d' ' -f1); \
	if [ "$$ACTUAL_SHA256" = "$$EXPECTED_SHA256" ]; then \
		echo "✓ SHA256 校验和验证通过"; \
		touch $(ISO_FILENAME).verified; \
	else \
		echo "✗ SHA256 校验和不匹配"; \
		echo "期望: $$EXPECTED_SHA256"; \
		echo "实际: $$ACTUAL_SHA256"; \
		rm -f $(ISO_FILENAME).verified; \
		exit 1; \
	fi

.PHONY: quick-check
quick-check:
	@echo "快速检查文件状态..."
	@if [ ! -f "$(ISO_FILENAME)" ]; then \
		echo "文件不存在，需要下载"; \
		exit 1; \
	fi
	@ACTUAL_SIZE=$$(stat -c%s "$(ISO_FILENAME)" 2>/dev/null || echo "0"); \
	if [ "$$ACTUAL_SIZE" -lt 1000000000 ]; then \
		echo "文件大小异常，需要重新下载"; \
		exit 1; \
	fi
	@if [ -f "$(ISO_FILENAME).verified" ] && \
		[ "$(ISO_FILENAME).verified" -nt "$(ISO_FILENAME)" ]; then \
		echo "✓ 文件已通过校验且完整"; \
	else \
		echo "文件未验证，进行校验..."; \
		$(MAKE) check-download; \
	fi

# 手动设置 SHA256（当网络有问题时）
.PHONY: set-sha256
set-sha256:
	@if [ -z "$(SHA256)" ]; then \
		echo "用法: make set-sha256 SHA256=<校验和值>"; \
		echo "例如: make set-sha256 SHA256=a435f6f393dda581172490eda9f683c32e495158a780b5a1de422ee77d98e909"; \
		exit 1; \
	fi
	@echo "$(SHA256)" > $(ISO_SHA256_CACHE)
	@echo "已手动设置 SHA256: $(SHA256)"

# 测试网络连接（支持代理）
.PHONY: test-network
test-network:
	@echo "测试网络连接..."
	@if [ -f "$(PROXY_CONFIG)" ]; then \
		echo "使用代理配置..."; \
		source $(PROXY_CONFIG); \
	fi
	@echo "测试 Ubuntu 官方源..."
	@if command -v curl >/dev/null 2>&1; then \
		echo "使用 curl 测试:"; \
		$(call with_proxy)curl --connect-timeout 5 --max-time 10 -I "$(ISO_SHA256_URL)" || echo "curl 失败"; \
	fi
	@if command -v wget >/dev/null 2>&1; then \
		echo "使用 wget 测试:"; \
		$(call with_proxy)wget --timeout=5 --tries=1 --spider "$(ISO_SHA256_URL)" && echo "wget 连接成功" || echo "wget 连接失败"; \
	fi

.PHONY: download
download:
	@echo "智能下载检查..."
	@if $(MAKE) quick-check >/dev/null 2>&1; then \
		echo "✓ ISO 文件已存在且完整，跳过下载"; \
	else \
		echo "需要下载或重新验证文件"; \
		if [ ! -f "$(ISO_FILENAME)" ]; then \
			echo "下载 ISO 文件..."; \
			sudo apt update && sudo apt install -y wget curl; \
			if [ -f "$(PROXY_CONFIG)" ]; then \
				echo "使用代理下载..."; \
				source $(PROXY_CONFIG); \
			fi; \
			$(call with_proxy)wget -c $(ISO_URLBASE)/$(ISO_FILENAME) || { \
				echo "下载失败"; \
				rm -f "$(ISO_FILENAME)"; \
				exit 1; \
			}; \
		fi; \
		echo "验证文件完整性..."; \
		$(MAKE) check-download; \
	fi

.PHONY: verify-only
verify-only:
	@if [ ! -f "$(ISO_FILENAME)" ]; then \
		echo "错误: ISO 文件不存在，请先下载"; \
		exit 1; \
	fi
	@$(MAKE) check-download

.PHONY: force-download
force-download:
	@echo "强制重新下载..."
	rm -f "$(ISO_FILENAME)" "$(ISO_SHA256_CACHE)" "$(ISO_FILENAME).verified"
	$(MAKE) download

.PHONY: clean-download
clean-download:
	@echo "清理下载文件..."
	rm -f "$(ISO_FILENAME)" "$(ISO_SHA256_CACHE)" "$(ISO_FILENAME).verified"

.PHONY: clean-all
clean-all: clean-download unset-proxy
	@echo "清理所有文件和配置..."

.PHONY: show-sha256
show-sha256: get-official-sha256
	@echo "官方 SHA256: $$(cat $(ISO_SHA256_CACHE))"
	@if [ -f "$(ISO_FILENAME)" ]; then \
		echo "本地 SHA256: $$(sha256sum $(ISO_FILENAME) | cut -d' ' -f1)"; \
	else \
		echo "本地文件不存在"; \
	fi

.PHONY: status
status:
	@echo "=== 文件状态检查 ==="
	@if [ -f "$(ISO_FILENAME)" ]; then \
		ACTUAL_SIZE=$$(stat -c%s "$(ISO_FILENAME)" 2>/dev/null || echo "0"); \
		echo "ISO 文件: 存在 ($$ACTUAL_SIZE 字节)"; \
	else \
		echo "ISO 文件: 不存在"; \
	fi
	@if [ -f "$(ISO_SHA256_CACHE)" ]; then \
		echo "SHA256 缓存: 存在 ($$(cat $(ISO_SHA256_CACHE)))"; \
	else \
		echo "SHA256 缓存: 不存在"; \
	fi
	@if [ -f "$(ISO_FILENAME).verified" ]; then \
		echo "验证标记: 存在"; \
	else \
		echo "验证标记: 不存在"; \
	fi
	@$(MAKE) proxy-status

# 帮助信息
.PHONY: help
help:
	@echo "Ubuntu 自动安装 ISO 制作工具"
	@echo ""
	@echo "主要命令:"
	@echo "  download        - 智能下载 ISO 文件"
	@echo "  quick-check     - 快速检查文件状态"
	@echo "  verify-only     - 仅验证现有文件"
	@echo "  status          - 显示所有文件状态"
	@echo ""
	@echo "代理设置:"
	@echo "  set-proxy PROXY=<地址>   - 设置代理"
	@echo "  unset-proxy              - 取消代理"
	@echo "  proxy-status             - 显示代理状态"
	@echo ""
	@echo "手动操作:"
	@echo "  set-sha256 SHA256=<值>   - 手动设置校验和"
	@echo "  test-network             - 测试网络连接"
	@echo "  force-download           - 强制重新下载"
	@echo ""
	@echo "清理:"
	@echo "  clean-download           - 清理下载文件"
	@echo "  clean-all                - 清理所有文件和配置"
	@echo ""
	@echo "代理示例:"
	@echo "  make set-proxy PROXY=http://127.0.0.1:7890"
	@echo "  make set-proxy PROXY=socks5://127.0.0.1:1080"

.PHONY: init
init:
	sudo apt install xorriso rsync
	( test -d $(ISO_ROOT) && mv -f $(ISO_ROOT) $(ISO_ROOT).$(shell date +%Y%m%d.%H%M%S) ) || true
	mkdir -p $(ISO_ROOT)
	sudo mkdir -p $(ISO_MOUNTPOINT)
	(mountpoint $(ISO_MOUNTPOINT) && sudo umount -q $(ISO_MOUNTPOINT)) || true
	sudo mount -o ro,loop $(ISO_FILENAME) $(ISO_MOUNTPOINT)
	rsync -av $(ISO_MOUNTPOINT)/. $(ISO_ROOT)/.
	sudo umount $(ISO_MOUNTPOINT)

.PHONY: setup
setup:
	chmod 755 $(ISO_ROOT)
	chmod 644 $(GRUBCFG_DEST)
	cp -f $(GRUBCFG_SRC) $(GRUBCFG_DEST)
	chmod 755 $(ISO_ROOT)
	cp -f $(USERDATA_SRC) $(USERDATA_DEST)
	cp -f $(METADATA_SRC) $(METADATA_DEST)
	rsync -av $(EXTRAS_SRCDIR)/. $(EXTRAS_DESTDIR)/.

.PHONY: setup-isolinux
setup-isolinux:
	chmod 755 $(ISO_ROOT)
	sudo apt install isolinux rsync syslinux-common
	cp $(GENISO_ISOLINUX) $(ISO_ROOT)/
	mkdir -p $(ISO_ROOT)/$(ISOLINUX_DIRNAME)
	rsync -av $(GENISO_ISOLINUX_MODULEDIR)/. $(ISO_ROOT)/$(ISOLINUX_DIRNAME)/.
	rsync -av $(ISOLINUX_CONFIGDIR)/. $(ISO_ROOT)/$(ISOLINUX_DIRNAME)/.

.PHONY: geniso
geniso:
	sudo env LANG=$(GENISO_LANG) xorriso -as mkisofs -volid $(GENISO_LABEL) \
	-output $(GENISO_FILENAME) \
	-eltorito-boot $(GENISO_BOOTIMG) \
	-eltorito-catalog $(GENISO_BOOTCATALOG) -no-emul-boot \
	-boot-load-size 4 -boot-info-table -eltorito-alt-boot \
	-no-emul-boot -isohybrid-gpt-basdat \
	-append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b --interval:local_fs:$(GENISO_START_SECTOR)d-$(GENISO_END_SECTOR)d::'$(ISO_FILENAME)' \
	-e '--interval:appended_partition_2_start_1782357s_size_8496d:all::' \
	--grub2-mbr --interval:local_fs:0s-15s:zero_mbrpt,zero_gpt:'$(ISO_FILENAME)' \
	"${ISO_ROOT}"

.PHONY: geniso-isolinux
geniso-isolinux:
	sudo env LANG=$(GENISO_LANG) xorriso -as mkisofs -volid $(GENISO_LABEL) \
	-output $(GENISO_FILENAME) \
	-eltorito-boot /$(shell basename $(GENISO_ISOLINUX)) \
	-eltorito-catalog $(GENISO_BOOTCATALOG) -no-emul-boot \
	-boot-load-size 4 -boot-info-table -eltorito-alt-boot \
	-no-emul-boot -isohybrid-gpt-basdat \
	-isohybrid-mbr $(GENISO_HYBRIDMBR) \
	"${ISO_ROOT}"

.PHONY: clean
clean:
	find . -type f -a -user "$(shell id -un)" -a -name '*~' -exec rm {} \; -print

.PHONY: clean-up-all
clean-up-all: clean
	sudo rm -rf iso_root
