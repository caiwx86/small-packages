#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2022-2025 ImmortalWrt.org

NAME="homeproxy"

RESOURCES_DIR="${RESOURCES_DIR:-/etc/$NAME/resources}"
RUN_DIR="${RUN_DIR:-/var/run/$NAME}"
LOG_PATH="$RUN_DIR/$NAME.log"
REPO_NAME="Loyalsoldier/surge-rules"
REPO_BRANCH="release"
SOURCE_BASE="${SOURCE_BASE:-https://cdn.jsdelivr.net/gh/$REPO_NAME@$REPO_BRANCH}"
RELEASE_API="${RELEASE_API:-https://api.github.com/repos/$REPO_NAME/releases/latest}"

mkdir -p "$RESOURCES_DIR" "$RUN_DIR"

log() {
	printf '%s %s\n' "$(date "+%Y-%m-%d %H:%M:%S")" "$*" >> "$LOG_PATH"
}

to_upper() {
	printf '%s\n' "$1" | tr '[:lower:]' '[:upper:]'
}

download() {
	local source_file="$1"
	local target_file="$2"

	curl -fsSL --retry 2 --connect-timeout 10 --max-time 60 \
		-o "$target_file" "$SOURCE_BASE/$source_file" && [ -s "$target_file" ]
}

exec 9>"$RUN_DIR/update_resources.lock"
if ! flock -n 9 > "/dev/null" 2>&1; then
	log "[RESOURCES] A task is already running."
	exit 2
fi

GITHUB_TOKEN="${GITHUB_TOKEN:-$(uci -q get homeproxy.config.github_token)}"
if [ -n "$GITHUB_TOKEN" ]; then
	NEW_VER="$(curl -fsSL --retry 2 --connect-timeout 10 --max-time 30 \
		-H "Authorization: Bearer $GITHUB_TOKEN" \
		"$RELEASE_API" | jsonfilter -e "@.tag_name")"
else
	NEW_VER="$(curl -fsSL --retry 2 --connect-timeout 10 --max-time 30 \
		"$RELEASE_API" | jsonfilter -e "@.tag_name")"
fi
if [ -z "$NEW_VER" ]; then
	log "[RESOURCES] Failed to get the latest version, please retry later."
	exit 1
fi

CURRENT=1
for RESOURCE in china_ip4 china_ip6 china_list gfw_list; do
	OLD_VER="$(cat "$RESOURCES_DIR/$RESOURCE.ver" 2>/dev/null || echo "NOT FOUND")"
	if [ "$OLD_VER" = "$NEW_VER" ]; then
		log "[$(to_upper "$RESOURCE")] Current version: $NEW_VER."
	else
		CURRENT=0
		log "[$(to_upper "$RESOURCE")] Local version: $OLD_VER, latest version: $NEW_VER."
	fi
done
[ "$CURRENT" -eq 0 ] || {
	log "[RESOURCES] You're already at the latest version."
	exit 3
}

TMP_DIR="$(mktemp -d "$RUN_DIR/resources-update.XXXXXX")" || exit 1
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

if ! download "cncidr.txt" "$TMP_DIR/cncidr.txt" || \
   ! download "direct.txt" "$TMP_DIR/china_list.txt" || \
   ! download "gfw.txt" "$TMP_DIR/gfw_list.txt"; then
	log "[RESOURCES] Update failed while downloading source lists."
	exit 1
fi

cp "$TMP_DIR/cncidr.txt" "$TMP_DIR/china_ip4.txt" && \
cp "$TMP_DIR/cncidr.txt" "$TMP_DIR/china_ip6.txt" && \
sed -i "/IP-CIDR6,/d; s/IP-CIDR,//g" "$TMP_DIR/china_ip4.txt" && \
sed -i "/IP-CIDR,/d; s/IP-CIDR6,//g" "$TMP_DIR/china_ip6.txt" && \
sed -i "s/^\\.//g" "$TMP_DIR/china_list.txt" "$TMP_DIR/gfw_list.txt"
if [ "$?" -ne 0 ]; then
	log "[RESOURCES] Update failed while processing source lists."
	exit 1
fi

for RESOURCE in china_ip4 china_ip6 china_list gfw_list; do
	if [ ! -s "$TMP_DIR/$RESOURCE.txt" ] || grep -qi '<html' "$TMP_DIR/$RESOURCE.txt"; then
		log "[$(to_upper "$RESOURCE")] Update failed: invalid processed list."
		exit 1
	fi
	printf '%s\n' "$NEW_VER" > "$TMP_DIR/$RESOURCE.ver" || exit 1
done

for RESOURCE in china_ip4 china_ip6 china_list gfw_list; do
	if ! mv -f "$TMP_DIR/$RESOURCE.txt" "$RESOURCES_DIR/$RESOURCE.txt" || \
	   ! mv -f "$TMP_DIR/$RESOURCE.ver" "$RESOURCES_DIR/$RESOURCE.ver"; then
		log "[$(to_upper "$RESOURCE")] Update failed: unable to replace list."
		exit 1
	fi
	log "[$(to_upper "$RESOURCE")] Successfully updated."
done

exit 0
