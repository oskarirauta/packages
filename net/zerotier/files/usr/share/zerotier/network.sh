#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. /usr/share/zerotier/constants.sh
	. /usr/share/zerotier/utils.sh

        config_load network
}

zerotier_ifdown_all() {

	find_ifd() {
		local ifd="$1"
		local proto

		config_get proto "$ifd" "proto"
		[ "$proto" = "zerotier" -a "$(interface_is_up $ifd)" = "1" ] && \
			ifdown "$ifd"
	}

	config_foreach find_ifd interface
}

zerotier_trigger_renewal() {

	find_ifd() {
		local ifd="$1"
		local proto

		config_get proto "$ifd" "proto"
		[ "$proto" = "zerotier" -a "$(interface_is_up $ifd)" = "1" ] && \
			ifconfig "$ifd" down
	}

	config_foreach find_ifd interface
}

zerotier_list_joined_networks() {

	local __networks

	for file in ${path}/networks.d/*.conf; do
		[[ "$file" = *.local.conf ]] || append __networks "$(basename $file .conf)"
	done
	echo "$__networks"
}

zerotier_list_devices() {

	local __devices

	add_device() {
		local ifd="$1"
		local proto nwid

		config_get proto "$ifd" "proto"
		config_get nwid "$ifd" "network_id"
		[ "$proto" = "zerotier" -a -n "$nwid" ] && \
			append __devices "${nwid}=${ifd}"
	}

	config_foreach add_device interface
	echo "$__devices"
}

zerotier_list_current_devices() {

	[ -f "${path}/devicemap" ] || return

	local __devices

	while read -r line; do
		append __devices "$line"
	done < "${path}/devicemap"

	echo "$__devices"
}

zerotier_join_network() {

	local nwid="$1"
	local cfg="$2"
	local __status __desc
	local __error="OK"

	__status=$($cli join "$nwid")

	[ "$__status" = "invalid network id" ] && {
		__error=NWID_INVALID
		__desc="invalid zerotier network id \"$nwid\" for $cfg"
	}

	[ "$__status" != "200 join OK" ] && {
		__error=SETUP_FAILED
		__desc="zerotier error while joining $nwid with ${cfg}: $__status"
	}

	export "$3=$__error"
	export "$4=$__desc"
}

zerotier_leave_network() {

	local nwid="$1"
	local cfg="$2"
	local __status __desc
	local __error="OK"

	__status=$($cli leave "$nwid")

	[ "$__status" = "invalid_network id" ] && {
		__error=NWID_INVALID
		__desc="invalid zerotier network id \"$nwid\" for $cfg"
	}

	[ "$__status" != "200 leave OK" ] && {
		__error=SETUP_FAILED
		__desc="zerotier error while leaving $nwid with ${cfg}: $__status"
	}

	export "$3=$__error"
	export "$4=$__desc"
}

zerotier_wait_tunnel() {

	local nwid="$1"
	local __cnt=0
	local __status

	while true; do
		__status="$($cli get ${nwid} status 2>&1)" || ""
		[ "$__status" != "REQUESTING_CONFIGURATION" -a -n "$__status" ] && break
		[ "$__cnt" -ge 60 ] && {
			__status="tunnel setup timed out"
			break
		}
		__cnt=$((__cnt + 1))
		sleep 1
	done

	[ "$__status" = "invalid format: must be a 16-digit (network) ID" ] && \
		__status=NWID_INVALID

	export "$2=$__status"
}

zerotier_get_nwid() {

	local ifd="$1"
	local __nwid __pattern

	while read -r line; do
		[ -n "$__nwid" ] && break
		__pattern=$(echo "$line" | awk '{ print $8 }')
		[ "$__pattern" = "$ifd" ] && \
			__nwid=$(echo "$line" | awk '{ print $3 '})
	done <<EOF
$($cli listnetworks)
EOF
	export "$2=$__nwid"
}

zerotier_network_count() {

	local __data="$($cli listnetworks 2>/dev/null)"
	local __header=$(echo "$__data" | head -n 1 | awk '{ print $1 }')
	local cnt

	[ "$__header" != "200" ] && cnt=1 || \
		cnt=$(echo "$__data" | wc -l)

	[ "$cnt" -ge 1 ] && cnt=$((cnt - 1))
	echo "$cnt"
}
