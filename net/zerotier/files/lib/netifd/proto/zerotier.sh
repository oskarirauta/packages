#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. ../netifd-proto.sh
	. /usr/share/zerotier/constants.sh
	. /usr/share/zerotier/network.sh
	. /usr/share/zerotier/config.sh
	. /usr/share/zerotier/parser.sh
	. /usr/share/zerotier/utils.sh
	. /usr/share/zerotier/service.sh
	init_proto "$@"
}

proto_zerotier_init_config() {
	no_device=1
	available=1
	no_proto_task=1
	teardown_on_l3_link_down=1

	proto_config_add_string "network_id"
	proto_config_add_string "ignore_route"
	proto_config_add_string "config_file"
	proto_config_add_boolean "copy_config_file"
}

proto_zerotier_setup() {

	local cfg="$1"
	local nwid ignore_route status msg

	( proto_add_host_dependency "$cfg" '' "wan" )

	zerotier_lock

	config_load network
	config_get nwid "$1" "network_id"
	config_get ignore_route "$cfg" "ignore_route"

	[ -z "$nwid" ] && {
		echo "zerotier network id not set for $cfg"
		proto_notify_error "$cfg" NWID_MISSING
		proto_block_restart "$cfg"
		return 1
	}

	[ "$(service_status_simple)" != "running" ] && {
		service_start
		sleep 2
	} || {
		status=$(zerotier_check_config)
		[ "$status" != "OK" ] && {
			echo "zerotier configuration has changed, reloading service"
			zerotier_trigger_renewal
			service_restart
			sleep 2
		}
	}

	[ "$(service_check)" -eq 0 ] && {
		echo "zerotier service does not appear to be running yet, retrying later"
		proto_notify_error "$cfg" NO_SERVICE
		return 1
	}

	zerotier_network_config "$cfg"
	zerotier_join_network "$nwid" "$cfg" status msg

	[ "$status" != "OK" ] && {
		echo "$msg"
		proto_notify_error "$cfg" $status
		proto_block_restart "$cfg"
		[ "$(zerotier_network_count)" -ge 1 ] || service_stop
		return 1
	}

	zerotier_wait_tunnel "$nwid" status

	[ "$status" != "OK" ] && {
		echo "zerotier failed to join $nwid with reason: $status"
		$cli leave "$nwid" &>/dev/null
		proto_notify_error "$cfg" $status
		[ "$status" != "tunnel setup timed out" ] && {
			proto_block_restart "$cfg"
			[ "$(zerotier_network_count)" -ge 1 ] || service_stop
		}
		return 1
	}

	sleep 1

	local addresses4 addresses6 gw routes ipaddr netmask target via metric src
	local json_data="$($cli -j listnetworks)"

	zerotier_get_addresses "$json_data" "$nwid" gw addresses4 addresses6

	[ -z "$addresses4" -a -z "$addresses6" ] && {
		echo "zerotier tunnel failed to get any IP address"
		proto_notify_error "$cfg" NO_IPADDRESS
                return 1
	}

	zerotier_get_routes "$json_data" "$nwid" "$gw" "$ignore_route" routes

	[ -z "$routes" ] && echo "warning, no routes for zerotier network $nwid found"

	proto_init_update "$cfg" 1

	for address in ${addresses4}; do
		zerotier_parse_address "$address" ipaddr netmask
		proto_add_ipv4_address "$ipaddr" "$netmask"
	done

	for address in ${addresses6}; do
		zerotier_parse_address "$address" ipaddr netmask
		proto_add_ipv6_address "$ipaddr" "$netmask"
	done

	for route in ${routes}; do
		zerotier_parse_route "$route" target netmask via src metric
		proto_add_ipv4_route "$target" "$netmask" "$via" "$src" "$metric"
	done

	proto_add_data
	zerotier_add_data "$nwid"
	[ -z "$routes" ] && json_add_string "warning" "unable to retrieve routes"
	proto_close_data
	proto_send_update "$cfg"
}

proto_zerotier_teardown() {
	local cfg="$1"
	local nwid status msg

	zerotier_lock

	[ "$(service_check)" -eq 0 ] && {
		echo "zerotier service does not appear to be running, retrying later"
		proto_notify_error "$cfg" NO_SERVICE
		return 1
	}

	config_load network
	config_get nwid "$cfg" "network_id"

        [ -z "$nwid" ] && {
		zerotier_get_nwid "$cfg" nwid
		[ -z "$nwid" ] && \
			echo "zerotier network id not set for ${cfg} when trying to leave network"
	}

	zerotier_leave_network "$nwid" "$cfg" status msg

	[ "$(zerotier_network_count)" -ge 1 ] || \
		service_stop
}

[ -n "$INCLUDE_ONLY" ] || {
	add_protocol zerotier
}
