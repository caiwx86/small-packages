#!/bin/sh

PATH="/usr/sbin:/usr/bin:/sbin:/bin"

binpath="$(uci get AdGuardHome.AdGuardHome.binpath 2>/dev/null)"
if [ -z "$binpath" ]; then
	uci set AdGuardHome.AdGuardHome.binpath="/tmp/AdGuardHome/AdGuardHome"
	binpath="/tmp/AdGuardHome/AdGuardHome"
fi

mkdir -p "${binpath%/*}"

upxflag="$(uci get AdGuardHome.AdGuardHome.upxflag 2>/dev/null)"

cleanup() {
	rm -f /var/run/update_core 2>/dev/null
	[ "$1" != "0" ] && touch /var/run/update_core_error
	exit "$1"
}

check_already_running(){
	# The lock file holds the PID; a leftover file from a killed process must
	# not block future updates forever.
	if [ -f /var/run/update_core ]; then
		local pid
		pid="$(cat /var/run/update_core 2>/dev/null)"
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			echo "已有任务在运行，退出"
			exit 2
		fi
		rm -f /var/run/update_core
	fi
}

check_wgetcurl(){
	if command -v curl >/dev/null 2>&1; then
		downloader="curl -L -k --retry 2 --connect-timeout 20 -o"
		return 0
	fi
	if command -v wget >/dev/null 2>&1; then
		downloader="wget --no-check-certificate -t 2 -T 20 -O"
		return 0
	fi

	echo "缺少 curl/wget，正在尝试安装..."
	if command -v apk >/dev/null 2>&1; then
		apk update >/dev/null 2>&1
		apk add curl >/dev/null 2>&1 || apk add wget >/dev/null 2>&1
	elif command -v opkg >/dev/null 2>&1; then
		opkg update >/dev/null 2>&1
		opkg install curl >/dev/null 2>&1 || opkg install wget-ssl >/dev/null 2>&1
	fi

	if command -v curl >/dev/null 2>&1; then
		downloader="curl -L -k --retry 2 --connect-timeout 20 -o"
		return 0
	fi
	if command -v wget >/dev/null 2>&1; then
		downloader="wget --no-check-certificate -t 2 -T 20 -O"
		return 0
	fi

	echo "错误：缺少 curl 和 wget"
	cleanup 1
}

get_owrt_arch(){
	# Prefer the package manager architecture: it encodes endianness and CPU
	# details that uname does not (for example mips64 vs. mips64el).
	local a
	a="$(opkg info kernel 2>/dev/null | awk -F': *' '/^Architecture:/{print $2;exit}')"
	[ -z "$a" ] && a="$(apk --print-arch 2>/dev/null)"
	echo "$a"
}

detect_arch(){
	local owrt machine
	owrt="$(get_owrt_arch)"
	machine="$(uname -m 2>/dev/null)"

	# AdGuard Home publishes separate armv5/armv6/armv7 and soft-float MIPS
	# builds; map OpenWrt's architecture strings to the release asset names.
	case "$owrt" in
	x86_64) Arch="amd64" ;;
	i386*|i486*|i586*|i686*) Arch="386" ;;
	aarch64*) Arch="arm64" ;;
	arm_cortex-a5*|arm_cortex-a7*|arm_cortex-a8*|arm_cortex-a9*|arm_cortex-a15*|arm_cortex-a17*) Arch="armv7" ;;
	arm_arm1176*|arm_mpcore*|arm_arm11*) Arch="armv6" ;;
	armeb*) Arch="" ;;
	arm_*) Arch="armv5" ;;
	mips64el*) Arch="mips64le_softfloat" ;;
	mips64*) Arch="mips64_softfloat" ;;
	mipsel*) Arch="mipsle_softfloat" ;;
	mips*) Arch="mips_softfloat" ;;
	powerpc64le*|ppc64le*) Arch="ppc64le" ;;
	riscv64*) Arch="riscv64" ;;
	*) Arch="" ;;
	esac

	if [ -z "$Arch" ]; then
		case "$machine" in
		x86_64|amd64) Arch="amd64" ;;
		i[3-6]86) Arch="386" ;;
		aarch64|arm64) Arch="arm64" ;;
		armv8l|armv7*|armv8*) Arch="armv7" ;;
		armv6*) Arch="armv6" ;;
		armv5*|arm) Arch="armv5" ;;
		mips64el*) Arch="mips64le_softfloat" ;;
		mips64*) Arch="mips64_softfloat" ;;
		mipsel*) Arch="mipsle_softfloat" ;;
		mips*) Arch="mips_softfloat" ;;
		ppc64le|powerpc64le) Arch="ppc64le" ;;
		riscv64) Arch="riscv64" ;;
		esac
	fi

	if [ -z "$Arch" ]; then
		echo "错误：不支持的架构：${owrt:-$machine}"
		cleanup 1
	fi

	echo "架构：${owrt:-$machine} -> $Arch"
}

check_latest_version(){
	check_wgetcurl

	release_channel="$(uci get AdGuardHome.AdGuardHome.release_channel 2>/dev/null)"
	[ -z "$release_channel" ] && release_channel="stable"

	if [ "$release_channel" = "beta" ]; then
		echo "正在检查最新版本（预发布通道）..."
		# /releases 返回时间倒序的所有 release，含 prerelease。取第一条 = 最新 beta。
		local api_url="https://api.github.com/repos/AdguardTeam/AdGuardHome/releases"
	else
		echo "正在检查最新版本（正式版通道）..."
		local api_url="https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest"
	fi

	local api_result
	api_result="$($downloader - "$api_url" 2>/dev/null)"
	latest_ver="$(echo "$api_result" | grep -oE '"tag_name": *"v[^"]+"' | head -1 | sed 's/.*"v\(.*\)".*/v\1/')"

	if [ -z "${latest_ver}" ]; then
		echo "检查最新版本失败，请稍后重试"
		cleanup 1
	fi

	if [ -x "$binpath" ]; then
		now_ver="$($binpath --version 2>/dev/null | grep -oE 'v[0-9.]+(-[A-Za-z0-9.]+)?' | head -1)"
		[ -z "$now_ver" ] && now_ver="$($binpath -c /dev/null --check-config 2>&1 | grep -oE 'v[0-9.]+(-[A-Za-z0-9.]+)?' | head -1)"
	else
		now_ver=""
	fi

	echo "本地版本：${now_ver:-无}，云端版本：${latest_ver}"

	if [ "$1" = "force" ]; then
		update_core
	elif [ -z "$now_ver" ]; then
		update_core
	elif [ "$(echo "$latest_ver" | sed 's/[^0-9.]//g')" != "$(echo "$now_ver" | sed 's/[^0-9.]//g')" ]; then
		# 只有云端版本号严格大于本地时才更新
		local newer
		newer="$(printf '%s\n%s' "$latest_ver" "$now_ver" | sed 's/^v//' | sort -Vr | head -1 | sed 's/^/v/')"
		if [ "$newer" = "$latest_ver" ] && [ "$latest_ver" != "$now_ver" ]; then
			update_core
		else
			echo "已是最新版本（本地版本更高或相同）"
			cleanup 0
		fi
	else
		echo "已是最新版本"
		cleanup 0
	fi
}

get_upx_arch(){
	case "$Arch" in
	amd64) echo "amd64" ;;
	386) echo "i386" ;;
	arm64) echo "arm64" ;;
	armv5|armv6|armv7) echo "arm" ;;
	mips_softfloat) echo "mips" ;;
	mipsle_softfloat) echo "mipsel" ;;
	ppc64le) echo "powerpc64le" ;;
	riscv64) echo "riscv64" ;;
	*) echo "" ;;
	esac
}

apply_upx(){
	[ -z "$upxflag" ] && return 0

	local target="${1:-$binpath}"
	[ -f "$target" ] || return 0

	local filesize
	filesize="$(ls -l "$target" 2>/dev/null | awk '{print $5}')"
	[ -z "$filesize" ] && return 0
	[ "$filesize" -le 8000000 ] && return 0

	local upx_arch
	upx_arch="$(get_upx_arch)"
	if [ -z "$upx_arch" ]; then
		echo "当前架构 $Arch 没有可用的 upx，跳过压缩"
		return 0
	fi

	echo "二进制文件大于 8MB，正在使用 upx 压缩..."
	fetch_upx "$upx_arch" || return 0

	local UPX_DIR="/tmp/upx-${upx_ver_nov}-${upx_arch}_linux"
	local UPX_BIN="${UPX_DIR}/upx"
	[ -x "$UPX_BIN" ] || { echo "upx 可执行文件未找到"; return 0; }

	local upx_out="/tmp/AdGuardHomeupdate/upx-packed-$$"
	"$UPX_BIN" $upxflag -o "$upx_out" "$target"
	local upxret=$?
	rm -rf "$UPX_DIR"

	if [ $upxret -eq 0 ] && [ -s "$upx_out" ]; then
		rm -f "$target"
		mv -f "$upx_out" "$target"
		chmod 755 "$target"
		echo "upx 压缩完成"
	else
		rm -f "$upx_out"
		echo "upx 压缩失败，保留原文件"
	fi
	return 0
}

fetch_upx(){
	local upx_arch="$1"
	[ -n "$upx_arch" ] || return 1

	upx_latest_ver="$($downloader - "https://api.github.com/repos/upx/upx/releases/latest" 2>/dev/null | grep -oE '"tag_name": *"[^"]+"' | head -1 | sed 's/.*"\(.*\)"/\1/')"
	[ -z "$upx_latest_ver" ] && { echo "获取 upx 版本失败"; return 1; }

	upx_ver_nov="$(echo "$upx_latest_ver" | sed 's/^v//')"
	local UPX_TGZ="/tmp/upx-${upx_ver_nov}-${upx_arch}_linux.tar.xz"
	local UPX_URL="https://github.com/upx/upx/releases/download/${upx_latest_ver}/upx-${upx_ver_nov}-${upx_arch}_linux.tar.xz"
	$downloader "$UPX_TGZ" "$UPX_URL" 2>&1
	[ $? -ne 0 ] && { echo "upx 下载失败"; return 1; }

	which xz >/dev/null 2>&1 || { opkg install xz >/dev/null 2>&1 || apk add xz >/dev/null 2>&1; }
	which xz >/dev/null 2>&1 || { echo "xz 不可用"; rm -f "$UPX_TGZ"; return 1; }

	xz -d -c "$UPX_TGZ" | tar -x -C "/tmp" >/dev/null 2>&1
	rm -f "$UPX_TGZ"

	[ -x "/tmp/upx-${upx_ver_nov}-${upx_arch}_linux/upx" ] || { echo "upx 解压失败"; return 1; }
}

update_core(){
	echo "正在更新 AdGuardHome 核心..."
	mkdir -p "/tmp/AdGuardHomeupdate"
	rm -rf /tmp/AdGuardHomeupdate/* 2>/dev/null

	detect_arch
	echo "架构：$Arch"

	echo "正在获取下载链接..."
	mkdir -p /tmp/run
	# 按通道生成下载源：beta 优先 static beta；stable 优先 static release
	if [ "$release_channel" = "beta" ]; then
		{
			echo "https://static.adguard.com/adguardhome/beta/AdGuardHome_linux_${Arch}.tar.gz"
			echo "https://github.com/AdguardTeam/AdGuardHome/releases/download/${latest_ver}/AdGuardHome_linux_${Arch}.tar.gz"
		} > /tmp/run/AdHlinks.txt
	else
		{
			echo "https://static.adguard.com/adguardhome/release/AdGuardHome_linux_${Arch}.tar.gz"
			echo "https://github.com/AdguardTeam/AdGuardHome/releases/download/${latest_ver}/AdGuardHome_linux_${Arch}.tar.gz"
		} > /tmp/run/AdHlinks.txt
	fi

	# Append user-provided mirrors from links.txt as additional fallbacks.
	# The shipped file also contains the official beta/release URLs; filter
	# them by channel so a stable system never falls back to a beta build.
	if [ -s /usr/share/AdGuardHome/links.txt ]; then
		while IFS= read -r link; do
			[ -n "$link" ] || continue
			case "$link" in
			*/adguardhome/beta/*) [ "$release_channel" = "beta" ] || continue ;;
			*/adguardhome/release/*) [ "$release_channel" = "beta" ] && continue ;;
			esac
			link="$(printf '%s' "$link" | sed "s#\${Arch}#$Arch#g; s#\${latest_ver}#$latest_ver#g")"
			printf '%s\n' "$link" >> /tmp/run/AdHlinks.txt
		done < /usr/share/AdGuardHome/links.txt
	fi

	local downloadbin=""
	local success=""

	while read link; do
		[ -z "$link" ] && continue
		eval link="$link"
		echo "尝试下载：$link"
		$downloader "/tmp/AdGuardHomeupdate/${link##*/}" "$link" 2>&1
		if [ $? -eq 0 ] && [ -s "/tmp/AdGuardHomeupdate/${link##*/}" ]; then
			downloadbin="/tmp/AdGuardHomeupdate/${link##*/}"
			success="1"
			echo "下载成功"
			break
		else
			echo "下载失败，尝试下一个..."
			rm -f "/tmp/AdGuardHomeupdate/${link##*/}"
		fi
	done < /tmp/run/AdHlinks.txt

	rm -f /tmp/run/AdHlinks.txt

	if [ -z "$success" ]; then
		echo "错误：所有下载源均失败"
		cleanup 1
	fi

	if [ "${downloadbin##*.}" = "gz" ]; then
		tar -zxf "$downloadbin" -C "/tmp/AdGuardHomeupdate/" 2>/dev/null
		if [ -d "/tmp/AdGuardHomeupdate/AdGuardHome" ]; then
			downloadbin="/tmp/AdGuardHomeupdate/AdGuardHome/AdGuardHome"
		else
			echo "错误：解压失败"
			cleanup 1
		fi
	fi

	chmod 755 "$downloadbin"
	echo "下载完成，如已配置 upx 则进行压缩..."
	apply_upx "$downloadbin"

	# Validate the downloaded file before touching the running service.
	local magic
	magic="$(head -c 4 "$downloadbin" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
	if [ "$magic" != "7f454c46" ]; then
		echo "错误：下载的文件不是有效的 ELF 可执行文件"
		cleanup 1
	fi
	if ! "$downloadbin" --version >/tmp/AdGuardHome_newver.log 2>&1; then
		echo "错误：下载的核心无法在当前架构运行"
		cleanup 1
	fi

	# Keep one previous core for a manual rollback.
	if [ -f "$binpath" ]; then
		if ! cp -f "$binpath" "${binpath}.old"; then
			echo "错误：无法保存旧核心（磁盘空间不足？）"
			cleanup 1
		fi
	fi

	echo "正在停止服务..."
	/etc/init.d/AdGuardHome stop nobackup 2>/dev/null

	echo "正在安装新二进制文件..."
	# Copy next to the target first so a full disk cannot destroy the old
	# binary; the final rename is atomic on the same filesystem.
	local newbin="${binpath}.new"
	if ! cp -f "$downloadbin" "$newbin"; then
		echo "复制失败 - 磁盘空间不足？"
		rm -f "$newbin"
		/etc/init.d/AdGuardHome start >/dev/null 2>&1
		cleanup 1
	fi
	if ! chmod 755 "$newbin"; then
		echo "设置执行权限失败"
		rm -f "$newbin"
		/etc/init.d/AdGuardHome start >/dev/null 2>&1
		cleanup 1
	fi
	if ! mv -f "$newbin" "$binpath"; then
		echo "替换核心失败"
		rm -f "$newbin"
		/etc/init.d/AdGuardHome start >/dev/null 2>&1
		cleanup 1
	fi

	# Refresh the version shown on the overview page without waiting for the
	# next visit to the base settings.
	local installed_ver
	installed_ver="$("$binpath" --version 2>/dev/null | grep -oE 'v[0-9.]+(-[A-Za-z0-9.]+)?' | head -1)"
	if [ -n "$installed_ver" ]; then
		uci -q set AdGuardHome.AdGuardHome.version="$installed_ver"
		uci -q set AdGuardHome.AdGuardHome.binmtime="$(stat -c %Y "$binpath" 2>/dev/null)"
		uci -q commit AdGuardHome
	fi

	rm -rf "/tmp/AdGuardHomeupdate" 2>/dev/null

	echo "正在启动服务..."
	/etc/init.d/AdGuardHome start 2>/dev/null

	# Give the daemon a few seconds, then roll back a broken new core.
	local i=0
	while [ "$i" -lt 10 ]; do
		/etc/init.d/AdGuardHome status >/dev/null 2>&1 && break
		sleep 1
		i=$((i + 1))
	done
	if [ "$(uci -q get AdGuardHome.AdGuardHome.enabled)" = "1" ] &&
		! /etc/init.d/AdGuardHome status >/dev/null 2>&1 && [ -f "${binpath}.old" ]; then
		echo "新核心启动失败，正在回滚..."
		if cp -f "${binpath}.old" "${binpath}.new" &&
			chmod 755 "${binpath}.new" &&
			mv -f "${binpath}.new" "$binpath"; then
			/etc/init.d/AdGuardHome start >/dev/null 2>&1
			echo "已回滚到上一版核心"
			cleanup 1
		fi
	fi

	echo "AdGuardHome 已成功更新至 ${latest_ver}"
	cleanup 0
}

trap "cleanup 1" SIGTERM SIGINT

check_already_running
echo $$ > /var/run/update_core
rm -f /var/run/update_core_error 2>/dev/null

check_latest_version "$1"
