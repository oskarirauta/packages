#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
        . /lib/functions.sh
	. /usr/share/libubox/jshn.sh
        . /lib/netifd/netifd-proto.sh
        . /usr/share/zerotier/constants.sh
}

zerotier_get_addresses() {

	local data="{ \"networks\": ${1}}"
	local nwid="$2"
	local __idx __nwid __gwaddr __addresses4 __addresses6

	json_load "${data}"

	add_address() {
		local __addr="$1"

		case "${__addr}" in
			*:*/*) append __addresses6 "${__addr}";;
			*.*/*) append __addresses4 "${__addr}";;
			*:*) append __addresses6 "${__addr}/${DEFAULT_MASK_IPV6}";;
			*.*) append __addresses4 "${__addr}/${DEFAULT_MASK_IPV4}";;
		esac

		[ -z "$__gwaddr" -a -n "$__addresses4" ] && \
			__gwaddr=$(echo "$__addresses4" | awk -F '/' '{ print $1 }')
	}

	json_select "networks"
	__idx=1

	while json_is_a ${__idx} object; do
		json_select ${__idx}
		json_get_var __nwid "nwid"
		[ "$__nwid" = "$nwid" ] && \
			json_for_each_item add_address "assignedAddresses"
		json_select ..
		__idx=$((__idx + 1))
	done
	json_select ..

	export "$3=$__gwaddr"
	export "$4=$__addresses4"
	export "$5=$__addresses6"
}

zerotier_parse_address() {

	local __addr=$(echo "$1" | awk -F '/' '{ print $1 }')
	local __mask=$(echo "$1" | awk -F '/' '{ print $2 }')

	export "$2=$__addr"
	export "$3=$__mask"
}

zerotier_get_routes() {

	local data="{ \"networks\": ${1}}"
	local nwid="$2"
	local __gateway="$3"
	local __localtarget="$4"
	local __idx __nwid __routes __localmask

	__localmask=$(echo "$__localtarget" | awk -F '/' '{ print $2 }')
	[ -n "$__localmask" ] && __localtarget=$(echo "$__localtarget" | awk -F '/' '{ print $1 }')

	json_load "${data}"

	add_route() {
		local __target __netmask __via __src __metric
		local __valid="0"

		json_select "$2"
		json_get_var __target "target"
		json_get_var __via "via"
		json_get_var __metric "metric"
		json_select ..

		[ -z "$__via" ] && __src="$__gateway" || __src=""
		__netmask=$(echo "$__target" | awk -F '/' '{ print $2 }')
		[ -z "$__netmask" ] && __netmask="24" || __target=$(echo "$__target" | cut -d / -f 1)

		[ -z "$__localtarget" ] && valid="1" || {
			[ -z "$__localmask" -a "$__target" != "$__localtarget" ] && valid="1"
			[ -n "$__localmask" -a \
				 "${__target}/${__netmask}" != "${__localtarget}/${__localmask}" ] && \
					valid="1"
		}

		[ "$valid" = "1" ] &&
			append __routes "${__target}/${__netmask}/${__via}/${__src}/${__metric}"
	}

	json_select "networks"
	__idx=1
	while json_is_a ${__idx} object; do
		json_select ${__idx}
		json_get_var __nwid "nwid"
		[ "$__nwid" = "$nwid" ] && \
			json_for_each_item add_route "routes"
		json_select ..
		__idx=$((__idx + 1))
	done
	json_select ..

	export "$5=$__routes"
}

zerotier_parse_route() {

	local __target=$(echo "$1" | awk -F '/' '{ print $1 }')
	local __mask=$(echo "$1" | awk -F '/' '{ print $2 }')
	local __via=$(echo "$1" | awk -F '/' '{ print $3 }')
	local __src=$(echo "$1" | awk -F '/' '{ print $4 }')
	local __metric=$(echo "$1" | awk -F '/' '{ print $5 }')

	export "$2=$__target"
	export "$3=$__mask"
	export "$4=$__via"
	export "$5=$__src"
	export "$6=$__metric"
}

zerotier_add_data() {

	local nwid="$1"
	local network_status="$($cli listnetworks | grep ${nwid})"

	[ -z "network_status" ] && {
		json_add_string "nwid" "$nwid"
		json_add_int "code" 0
		json_add_string "status" "failed to retrieve network status"
	} || {
		json_add_string "nwid" "$nwid"
		json_add_int "code" "$(echo $network_status | awk '{ print $1 }')"
		json_add_string "name" "$(echo $network_status | awk '{ print $4 }')"
		json_add_string "hwaddr" "$(echo $network_status | awk '{ print $5 }')"
		json_add_string "status" "$(echo $network_status | awk '{ print $6 }')"
		json_add_string "type" "$(echo $network_status | awk '{ print $7 }')"
	}
}
