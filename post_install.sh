#!/bin/sh
	
# Setup services
iocage exec "$1" sysrc "traefik_conf=/config/traefik.toml"
iocage exec "$1" sysrc "traefik_enable=YES"
iocage exec "$1" sysrc "firewall_script=/config/firewall.rules"
iocage exec "$1" sysrc "firewall_enable=YES"