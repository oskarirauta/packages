#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {

	initscript="zerotier_service"

	. /lib/functions.sh
	. /lib/functions/procd.sh
	. /usr/share/zerotier/constants.sh
	. /usr/share/zerotier/network.sh
	. /usr/share/zerotier/config.sh

	config_load network
}

service_check() {

	local __exe

	[ -f "${path}/zerotier-one.port" -a -f "${path}/zerotier-one.pid" ] || {
		echo "0"
		return
	}

	__exe=$(cat "${path}/zerotier-one.pid")

	__exe=$(readlink "/proc/${__exe}/exe")
	[ -z "$__exe" ] && {
		echo "0"
		return
	}

	__exe=$(basename "$__exe")
	[ "$__exe" != "zerotier-one" ] && {
		echo "0"
		return
	}

	echo "1"
}

service_triggers() {
	procd_add_reload_interface_trigger wan
}

service_data() {
	return 0
}

service_status() {

	local __status=$(_procd_status "zerotier_service" "zerotier")
	[ "$__status" = "active with no instances" -o "$__status" = "unknown instance \"zerotier\"" ] && \
		__status="inactive" || [ "$__status" = "stopped" ] && __status="inactive"
	echo "$__status"
}

service_status_simple() {

	local __status=$(_procd_status "zerotier_service" "zerotier")
	[ "$__status" = "starting" -o "$__status" = "restarting" ] && __status="running"
	echo "$__status"
}

start_server() {

	local __port
	config_get __port "globals" "zerotier_port" "$DEFAULT_PORT"

	procd_open_instance "zerotier"
	procd_set_param command "$server" -p${__port} ${path}
	procd_set_param stderr 1
	procd_set_param respawn
	procd_close_instance
}

service_start() {

	[ "$(service_status_simple)" = "running" ] && {
		echo "zerotier service is already running"
		return 0
	}

	procd_lock
	zerotier_generate_config
	procd_open_service "zerotier_service" "zerotier"
	start_server
	procd_close_service "add"
	sleep 1
}

service_stop() {

	local __status

	procd_lock
	__status="$(service_status)"
	[ "$__status" = "starting" -o "$__status" = "restarting" ] && {
		sleep 2
		__status="$(service_status)"
	}
	[ "$__status" = "running" ] || return 0

	zerotier_ifdown_all
	procd_kill "zerotier_service" "zerotier"
	sleep 1
}

service_restart() {

	local __method="set"
	local __status

	procd_lock
	__status="$(service_status)"

	[ "$(service_status_simple)" = "running" ] || {
		[ "$(service_status__simple)" = "inactive" ] && __method="add"
		return
	}

	__status=$(service_status)

	[ "$__status" == "starting" ] && {
		sleep 1
		__status=$(service_status)
	}

	[ "$__status" = "running" ] && {
		procd_kill "zerotier_service" "zerotier"
		sleep 1
	}

	rm -rf "${path}/networks.d"
	zerotier_generate_config

	procd_open_service "zerotier_service" "zerotier"
	start_server
	procd_close_service "$__method"
	sleep 1
}
