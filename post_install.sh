#!/bin/sh
	
# Setup services
sysrc "traefik_conf=/config/traefik.toml"
sysrc "traefik_enable=YES"
sysrc "firewall_script=/config/firewall.rules"
sysrc "firewall_enable=YES"