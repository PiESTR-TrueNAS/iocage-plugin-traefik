#!/usr/local/bin/bash
# This file contains the install script to install traefik as Jailman Reverse Proxy

# init plugin
initplugin "$1"

# Set default variable values
influxdb_database="${influxdb_database:-$1}"
influxdb_user="${influxdb_user:-$influxdb_database}"
domain_name="${domain_name:-$jail_ip}"
productionurl="https://acme-v02.api.letsencrypt.org/directory"
stagingurl="https://acme-staging-v02.api.letsencrypt.org/directory"

# Copy the needed config files
iocage exec "${1}" mkdir /config/temp/
iocage exec "${1}" mkdir /config/dynamic/
cp "${includes_dir}"/traefik.toml /mnt/"${global_dataset_config}"/"${1}"/
cp "${includes_dir}"/firewall.rules /mnt/"${global_dataset_config}"/"${1}"/
cp "${includes_dir}"/ssl.yml /mnt/"${global_dataset_config}"/"${1}"/dynamic/
cp "${includes_dir}"/buildin_middlewares.toml /mnt/"${global_dataset_config}"/"${1}"/dynamic/buildin_middlewares.toml

cp "${includes_dir}"/buildin_middlewares.toml /mnt/"${global_dataset_config}"/"${1}"/dynamic/buildin_middlewares.toml
if [ -z "$cert_wildcard_domain" ];
then
	echo "wildcard not set, using non-wildcard config..."
	cp "${includes_dir}"/dashboard.toml /mnt/"${global_dataset_config}"/"${1}"/dynamic/dashboard.toml
else
	echo "wildcard set, using wildcard config..."
	cp "${includes_dir}"/dashboard_wildcard.toml /mnt/"${global_dataset_config}"/"${1}"/dynamic/dashboard.toml
fi

# Create DNS verification env-vars (as required by traefik)
dnsenv=$(printenv | grep "${1}_cert_env_" | grep -o 'env_.*' | cut -f2- -d_ | tr "\n" " "; echo)
iocage exec "$1" sysrc "traefik_env=${dnsenv}"

# Replace placeholders with actual config
iocage exec "${1}" sed -i '' "s|placeholderemail|${cert_email}|" /config/traefik.toml
iocage exec "${1}" sed -i '' "s|placeholderprovider|${dns_provider}|" /config/traefik.toml
iocage exec "${1}" sed -i '' "s|placeholderdashboardhost|${domain_name}|" /config/dynamic/dashboard.toml
iocage exec "${1}" chown -R traefik:traefik /config

if [ -z "$cert_wildcard_domain" ];
then
	echo "wildcard not set, not enabling wildcard config..."
else
	echo "wildcard set, enabling wildcard config..."
	iocage exec "${1}" sed -i '' "s|placeholderwildcard|${cert_wildcard_domain}|" /config/dynamic/dashboard.toml
fi

if [ -z "$cert_staging" ] || [ "$cert_staging" = "false" ];
then
	echo "staging not set, using production server for LetsEncrypt"
	iocage exec "${1}" sed -i '' "s|leserverplaceholder|${productionurl}|" /config/traefik.toml
else
	echo "staging set, using staging server for LetsEncrypt"
	iocage exec "${1}" sed -i '' "s|leserverplaceholder|${stagingurl}|" /config/traefik.toml
fi

if [ -z "$cert_strict_sni" ] || [ "$cert_strict_sni" = "false" ];
then
	echo "Strict SNI not set. Keeping strict SNI disabled..."
else
	echo "Strict SNI set to ENABLED. Enabling Strict SNI."
	echo "      sniStrict: true" >> /config/dynamic/ssl.yml
fi

if [ -z "$dashboard" ] || [ "$dashboard" = "false" ];
then
	echo "dashboard disabled. Keeping the dashboard disabled..."
	iocage exec "${1}" sed -i '' "s|dashplaceholder|false|" /config/traefik.toml
else
	echo "Dashboard set to on, enabling dashboard"
	iocage exec "${1}" sed -i '' "s|dashplaceholder|true|" /config/traefik.toml
fi
if [ -n "${link_influxdb}" ]
then
  echo "Checking if the influxdb jail and database exist..."
  if [[ -d "${global_dataset_iocage}"/jails/"${link_influxdb}" ]]; then
    DB_EXISTING=$(iocage exec "${link_influxdb}" curl -G http://127.0.0.1:8086/query --data-urlencode 'q=SHOW DATABASES' | jq '.results [] | .series [] | .values []' | grep "${influxdb_database}" | sed 's/"//g' | sed 's/^ *//g' || echo "")
    if [[ "$influxdb_database" == "$DB_EXISTING" ]]; then
      echo "${link_influxdb} jail with database ${influxdb_database} already exists. Skipping database creation... "
    else
      echo "${link_influxdb} jail exists, but database ${influxdb_database} does not. Creating database ${influxdb_database}."
      # shellcheck disable=SC2027,2086
      iocage exec "${link_influxdb}" "curl -XPOST -u ${influxdb_user}:${influxdb_password} http://"${link_influxdb_ip4_addr%/*}":8086/query --data-urlencode 'q=CREATE DATABASE ${influxdb_database}'"
      echo "Database ${influxdb_database} created with username ${influxdb_user} with password ${influxdb_password}."
     fi
	cat "${includesdir}/metrics.conf" >> /mnt/"${global_dataset_config}"/"${1}"/traefik.toml
	iocage exec "${1}" sed -i '' "s|INFLUXDBHOST|${link_influxdb_ip4_addr%/*}|" /config/traefik.toml
	iocage exec "${1}" sed -i '' "s|INFLUXDBDB|${influxdb_database}|" /config/traefik.toml
	iocage exec "${1}" sed -i '' "s|INFLUXDBUSER|${influxdb_user}|" /config/traefik.toml
	iocage exec "${1}" sed -i '' "s|INFLUXDBPASS|${influxdb_password}|" /config/traefik.toml
  else
    echo "Influxdb jail does not exist. Traefik metrics requires a Influxdb jail. Please install the Influxdb jail."
    exit 1
  fi
fi

# Start services
iocage exec "$1" service ipfw start
iocage exec "$1" service traefik start

if [ -z "$dashboard" ] || [ "$dashboard" = "false" ];
then
	exitplugin "${1}" "Traefik installed successfully, but you can not connect to the dashboard, as you had it disabled."
else
	exitplugin "${1}" "Traefik installed successfully, you can now connect to the traefik dashboard: https://${domain_name}"
fi

