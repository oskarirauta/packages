#!/bin/sh

DEFAULT_PORT=9993
DEFAULT_MASK_IPV4="24"
DEFAULT_MASK_IPV6="88"

lockfile=/tmp/.zerotier_lock
server=/usr/bin/zerotier-one
path=/var/lib/zerotier-one
cli=/usr/bin/zerotier-cli
