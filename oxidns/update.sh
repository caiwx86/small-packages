#!/bin/bash
set -euo pipefail

# 用法: ./update.sh <version> <commit_hash>
# 示例: ./update.sh 1.5.2 abc123def456...

VERSION="$1"
COMMIT_HASH="$2"
MAKEFILE="Makefile"

if [[ -z "$VERSION" || -z "$COMMIT_HASH" ]]; then
  echo "Usage: $0 <version> <commit_hash>"
  exit 1
fi

# 计算新源文件的时间戳（取当前日期）
SOURCE_DATE=$(date +%Y-%m-%d)

echo "Updating ${MAKEFILE}: version=${VERSION}, commit=${COMMIT_HASH}, date=${SOURCE_DATE}"

# 备份原文件
cp "${MAKEFILE}" "${MAKEFILE}.bak"

# 更新 PKG_VERSION
sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=${VERSION}/" "${MAKEFILE}"

# 更新 PKG_SOURCE_VERSION
sed -i "s/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=${COMMIT_HASH}/" "${MAKEFILE}"

# 更新 PKG_SOURCE_DATE
sed -i "s/^PKG_SOURCE_DATE:=.*/PKG_SOURCE_DATE:=${SOURCE_DATE}/" "${MAKEFILE}"

# 更新 PKG_SOURCE（Subdir 依赖 PKG_VERSION）
sed -i "s/^PKG_SOURCE_SUBDIR:=.*/PKG_SOURCE_SUBDIR:=\$(PKG_NAME)-\$(PKG_VERSION)/" "${MAKEFILE}"

# 重置 PKG_RELEASE
sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=1/" "${MAKEFILE}"

# 清除旧的 PKG_MIRROR_HASH（首次构建时会自动生成正确的 hash）
sed -i "s/^PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/" "${MAKEFILE}"

# 显示变更
echo "--- Diff ---"
diff "${MAKEFILE}.bak" "${MAKEFILE}" || true

# 清理备份
rm -f "${MAKEFILE}.bak"

echo "Update complete."