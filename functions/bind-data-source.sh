#!/usr/bin/env bash
set -euo pipefail

source functions/base.sh

get_influxdb_vcap_service() {
    jq '[.[][] | select(.label=="csb-aws-influxdb") ] | first | select (.!=null)' <<<"${VCAP_SERVICES}"
}

get_prometheus_vcap_service() {
    # search for a sql service looking at the label
    jq '[.[][] | select(.credentials.prometheus) ] | first | select (.!=null)' <<<"${VCAP_SERVICES}"
}

get_delete_datasources_object() {
  local datasource=${1}
  local orgId=${2}

  databases=$(jq -r '.credentials.bound_databases' <<<"${datasource}")

  jq -r '.[]' <<< "${databases}" | while read -r database; do
    cat <<EOF
- name: "${database}"
  orgId: ${orgId}
EOF
  done
}

get_datasources_object() {
  local datasource=${1}
  local orgId=${2}

  name=$(jq -r '.name' <<<"${datasource}")
  databases=$(jq -r '.credentials.bound_databases' <<<"${datasource}")
  url="$(echo ${datasource} | jq -r '.credentials.url')"
  username="$(echo ${datasource} | jq -r '.credentials.username')"
  password="$(echo ${datasource} | jq -r '.credentials.password')"

  jq -r '.[]' <<< "${databases}" | while read -r database; do
    cat <<EOF
- name: "${database}"
  type: influxdb
  access: proxy
  url: "${url}"
  database: "${database}"
  user: "${username}"
  orgId: ${orgId}
  readOnly: false
  editable: true
  secureJsonData:
    password: "${password}"
EOF
  done
}

set_vcap_datasource_influxdb() {
  local datasource="${1}"
  local orgId="1"

  local label=$(jq -r '.label' <<<"${datasource}")
  if [[ "${label}" = "csb-aws-influxdb" ]]; then

    name=$(jq -r '.name' <<<"${datasource}")
    mkdir -p "${APP_ROOT}/datasources"

    # Be careful, this is a HERE doc with tabs indentation!!
    cat <<-EOF > "${APP_ROOT}/datasources/${name}.yml"
apiVersion: 1

deleteDatasources:
$(get_delete_datasources_object "${datasource}" "${orgId}")

datasources:
$(get_datasources_object "${datasource}" "${orgId}")
EOF
  fi
}

set_vcap_datasource_prometheus() {
  local datasource="${1}"

  local label=$(jq -r '.label' <<<"${datasource}")
  if [[ "${label}" != "csb-aws-influxdb" ]]; then

    local name=$(jq -r '.name' <<<"${datasource}")
    local user=$(jq -r '.credentials.prometheus.user | select (.!=null)' <<<"${datasource}")
    local pass=$(jq -r '.credentials.prometheus.password | select (.!=null)' <<<"${datasource}")
    local url=$(jq -r '.credentials.prometheus.url' <<<"${datasource}")
    local auth="true"

    [[ -z "${user}" ]] && auth="false"
    mkdir -p "${APP_ROOT}/datasources"

    # Be careful, this is a HERE doc with tabs indentation!!
    cat <<-EOF > "${APP_ROOT}/datasources/${HOME_ORG_ID}-${name}.yml"
	apiVersion: 1

	# list of datasources that should be deleted from the database
	deleteDatasources:
	- name: ${name}
	  orgId: ${HOME_ORG_ID}

	# list of datasources to insert/update depending
	# what's available in the database
	datasources:
	- name: ${name}
	  type: prometheus
	  access: proxy
	  orgId: ${HOME_ORG_ID}
	  url: "${url}"
	  basicAuth: ${auth}
	  basicAuthUser: ${user}
	  jsonData:
	    timeInterval: "${DEFAULT_DATASOURCE_TIMEINTERVAL}"
	  secureJsonData:
	    basicAuthPassword: ${pass}
	  withCredentials: false
	  isDefault: true
	  editable: ${DEFAULT_DATASOURCE_EDITABLE}
	EOF
	fi
}


set_vcap_datasource_alertmanager() {
    local datasource="${1}"

    local label=$(jq -r '.label' <<<"${datasource}")
    local name=$(jq -r '.name' <<<"${datasource}")
    local user=$(jq -r '.credentials.prometheus.user | select (.!=null)' <<<"${datasource}")
    local pass=$(jq -r '.credentials.prometheus.password | select (.!=null)' <<<"${datasource}")
    local url=$(jq -r '.credentials.alertmanager.url' <<<"${datasource}")
    local auth="true"

    [[ -z "${user}" ]] && auth="false"
    mkdir -p "${APP_ROOT}/datasources"

    # Be careful, this is a HERE doc with tabs indentation!!
    cat <<-EOF > "${APP_ROOT}/datasources/${HOME_ORG_ID}-${name}-alertmanager.yml"
	apiVersion: 1

	# list of datasources to insert/update depending
	# what's available in the database
	datasources:
	- name: ${name} AlertManager
	  type: camptocamp-prometheus-alertmanager-datasource
	  access: proxy
	  orgId: ${HOME_ORG_ID}
	  url: "${url}"
	  basicAuth: ${auth}
	  basicAuthUser: ${user}
	  secureJsonData:
	    basicAuthPassword: ${pass}
	  withCredentials: false
	  isDefault: false
	  editable: ${DEFAULT_DATASOURCE_EDITABLE}
	EOF

    echo "Installing camptocamp-prometheus-alertmanager-datasource ${GRAFANA_ALERTMANAGER_VERSION} ..."
    grafana-cli --pluginsDir "$GF_PATHS_PLUGINS" plugins install camptocamp-prometheus-alertmanager-datasource ${GRAFANA_ALERTMANAGER_VERSION}
}

set_datasource() {
  datasource="${1}"
  local alertmanager_prometheus_exists

  if [[ -n "${datasource}" ]]; then
    echo "Setting datasource ${datasource}"

    set_vcap_datasource_prometheus "${datasource}"
    set_vcap_datasource_influxdb "${datasource}"

    # Check if AlertManager for the Prometheus service instance has been enabled by the user first
    # before installing the AlertManager Grafana plugin and configuring the AlertManager Grafana datasource
    alertmanager_prometheus_exists=$(jq -r '.credentials.alertmanager.url' <<<"${datasource}")
    if [[ -n "${alertmanager_prometheus_exists}" ]] && [[ "${alertmanager_prometheus_exists}" != "null" ]]
    then
        set_vcap_datasource_alertmanager "${datasource}"
    fi
  fi
}

set_datasources() {
  if [[ -z ${DATASOURCE_BINDING_NAMES} ]]; then
    echo "No datasource binding names set, looking for prometheus or influxdb config"
    set_datasource "$(get_prometheus_vcap_service)"
    set_datasource "$(get_influxdb_vcap_service)"
  else
    for datasource_binding in ${DATASOURCE_BINDING_NAMES//,/ }; do
      echo "Retrieving binding service for ${datasource_binding}"
      set_datasource "$(get_binding_service "${VCAP_SERVICES}" "${datasource_binding}")"
    done
  fi
}
