#!/bin/sh

PATH="/usr/sbin:/usr/bin:/sbin:/bin"

configpath="$(uci -q get AdGuardHome.AdGuardHome.configpath)"
[ -n "$configpath" ] || exit 0

while :; do
	sleep 10
	if [ -f "$configpath" ]; then
		/etc/init.d/AdGuardHome do_redirect 1
		break
	fi
done

exit 0
