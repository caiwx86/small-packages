#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2023 ImmortalWrt.org

SCRIPTS_DIR="/etc/homeproxy/scripts"

"$SCRIPTS_DIR"/update_resources.sh

"$SCRIPTS_DIR"/update_subscriptions.uc
