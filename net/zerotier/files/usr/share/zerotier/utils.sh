#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
	. /usr/share/zerotier/constants.sh
}

interface_is_up() {
	local __result=$(ubus call network.interface.${1} status 2>/dev/null)
	[ -z "$__result" ] && __result="false" || __result=$(jsonfilter -s "$__result" -e "@['up']")
	[ "$__result" = "true" ] && echo "1" || echo "0"
}

device_is_up() {
	local __result=$(ubus call network.device status "{ \"name\": \"$1\" }" 2>/dev/null)
	[ -z "$__result" ] && __result="false" || __result=$(jsonfilter -s "$__result" -e "@['up']")
	[ "$__result" = "true" ] && echo "1" || echo "0"
}

network_is_up() {
	local __result=$($cli listnetworks | grep "$1")
	[ -n "$__result" ] && echo "1" || echo "0"
}

zerotier_lock() {

	flock -n 1000 &>/dev/null
	[ "$?" != "0" ] && {
		exec 1000 > ${lockfile}
		flock 1000
		[ "$?" != "0" ] && \
			logger -t netifd -p daemon.warn zerotier protocol failure with lockfile
	}
}
