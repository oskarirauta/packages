#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
        . /lib/functions.sh
	. /usr/share/zerotier/constants.sh
	. /usr/share/zerotier/network.sh

	config_load network
}

zerotier_network_config() {

	local cfg="$1"
	local proto network_id config_file copy_config_file

	config_get proto "$cfg" "proto"
	config_get network_id "$cfg" "network_id"
	config_get config_file "$cfg" "config_file"
	config_get copy_config_file "$cfg" "copy_config_file"

	[ "$proto" = "zerotier" -a -n "$network_id" ] || return
	[ -n "$config_file" -a -f "$config_file" ] || return

	[ "$copy_config_file" -eq 1 ] && \
		cp "$config_file" "${path}/networks.d/${network_id}.local.conf" || \
		ln -s "$config_file" "${path}/networks.d/${network_id}.local.conf"
}

zerotier_generate_secret_identity() {

	local __secret

	mkdir -p "${path}"
	rm -f "${path}/identity.secret"

	config_get __secret "globals" "zerotier_secret"

	[ -z "$__secret" ] && {

		/usr/bin/zerotier-idtool generate "${path}/identity.secret" &>/dev/null
		[ $0 -ne 0 ] && {
			rm -f "${path}/identity.secret"
			echo "zerotier failed to generate secret identity"
			return
		}
		__secret=$(cat "${path}/identity.secret")
		config_set "globals" "zerotier_secret" "${__secret}"
	} || echo "$__secret" > ${path}/identity.secret
}

zerotier_generate_devicemap() {

	mkdir -p "${path}"
	rm -f "${path}/devicemap"

	add_device() {
		local ifd="$1"
		local proto nwid

		config_get proto "$ifd" "proto"
		config_get nwid "$ifd" "network_id"
		[ "$proto" = "zerotier" -a -n "$nwid" ] &&  \
			echo "${nwid}=${ifd}" >> ${path}/devicemap
	}

	config_foreach add_device interface
}

zerotier_remove_runtime_files() {

	rm -rf "${path}/zerotier-one.pid" "${path}/zerotier-one.port" \
		"${path}/planet" "${path}/authtoken.secret" \
		"${path}/controller.d" "${path}/peers.d"
}

zerotier_remove_all_files() {

	zerotier_remove_runtime_files
	rm -rf "${path}/identity.secret" "${path}/identity.public" \
		"${path}/devicemap" "${path}/networks.d"
}

zerotier_generate_config() {

	zerotier_remove_all_files
	mkdir -p "${path}/networks.d"

	zerotier_generate_secret_identity
	zerotier_generate_devicemap
}

zerotier_check_config() {

	local __result="OK"
	local __secret __cur_secret __port  __cur_port

	config_get __secret "globals" "zerotier_secret"
	config_get __port "globals" "zerotier_port" "$DEFAULT_PORT"

	[ -d "${path}/networks.d" ] || __result="path"
	[ -f "${path}/zerotier-one.port" ] && __cur_port=$(cat "${path}/zerotier-one.port")

	[ -n "$__secret" -a -f "${path}/identity.secret" ] && {

		__cur_secret=$(cat "${path}/identity.secret")
		[ "$__cur_secret" = "$__secret" ] || __result="secret"

	} || __result="secret"

	[ -z "$__cur_port" -o "$__cur_port" != "$__port" ] && __result="port"

	[ "$(zerotier_list_devices)" != "$(zerotier_list_current_devices)" ] && \
		__result="devices"

	echo "${__result}"
}
