#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -euo pipefail

# See bin/finalize to check predefined vars
ROOT="/home/vcap"
export AUTH_ROOT="${ROOT}/auth"
#export GRAFANA_ROOT=$(find ${ROOT}/deps -name grafana -type d -maxdepth 2)
export GRAFANA_ROOT=$GRAFANA_ROOT
#export SQLPROXY_ROOT=$(find ${ROOT}/deps -name cloud_sql_proxy -type d -maxdepth 2)
export SQLPROXY_ROOT=$SQLPROXY_ROOT
export YQ_ROOT=${YQ_ROOT}
export APP_ROOT="${ROOT}/app"
export GRAFANA_DASHBOARD_ROOT=${APP_ROOT}/dashboards
export GRAFANA_ALERTING_ROOT=${APP_ROOT}/alerting
export GRAFANA_CFG_INI="${ROOT}/app/grafana.ini"
export GRAFANA_CFG_PLUGINS="${ROOT}/app/plugins.txt"
export GRAFANA_USER_CONFIG_ROOT="${ROOT}/app/users"
export PATH=${PATH}:${GRAFANA_ROOT}/bin:${SQLPROXY_ROOT}:${YQ_ROOT}

### Bindings
# Prometheus or InfluxDB datasources
export DATASOURCE_BINDING_NAMES="${DATASOURCE_BINDING_NAMES:-}"
# SQL DB
export DB_BINDING_NAME="${DB_BINDING_NAME:-}"

# Exported variables used in default.ini config file
export DOMAIN=${DOMAIN:-$(jq -r '.uris[0]' <<<"${VCAP_APPLICATION}")}
export URL="${URL:-http://$DOMAIN/}"
export HOME_DASHBOARD_UID="${HOME_DASHBOARD_UID:-home}"
export HOME_ORG_ID="${HOME_ORG_ID:-1}"
export ADMIN_USER="${ADMIN_USER:-${GF_SECURITY_ADMIN_USER:-admin}}"
export ADMIN_PASS="${ADMIN_PASS:-${GF_SECURITY_ADMIN_PASSWORD:-admin}}"
export EMAIL="${EMAIL:-grafana@$DOMAIN}"
export SECRET_KEY="${SECRET_KEY:-}"
export DEFAULT_DATASOURCE_EDITABLE="${DEFAULT_DATASOURCE_EDITABLE:-false}"
export DEFAULT_DATASOURCE_TIMEINTERVAL="${DEFAULT_DATASOURCE_TIMEINTERVAL:-60s}"

# Variables exported, they are automatically filled from the
# service broker instances.
# See reset_DB for default values!
export DB_TYPE="sqlite3"
export DB_USER="root"
export DB_HOST=""
export DB_PASS=""
export DB_PORT=""
export DB_NAME="grafana"
export DB_CA_CERT=""
export DB_CLIENT_CERT=""
export DB_CLIENT_KEY=""
export DB_CERT_NAME=""
export DB_TLS=""

source functions/generate-alerts.sh
source functions/pre-process.sh
source functions/bind-db.sh

###

# exec process in bg
launch() {
    (
        echo "Launching pid=$$: '$@'"
        {
            exec $@  2>&1;
        }
    ) &
    pid=$!
    sleep 15
    if ! ps -p ${pid} >/dev/null 2>&1
    then
        echo
        echo "Error launching '$@'."
        rvalue=1
    else
        echo "Pid=${pid} running"
        rvalue=0
    fi
    return ${rvalue}
}

random_string() {
    (
        cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-32} | head -n 1 || true
    )
}

get_influxdb_vcap_service() {
    jq '[.[][] | select(.label=="csb-aws-influxdb") ] | first | select (.!=null)' <<<"${VCAP_SERVICES}"
}

get_prometheus_vcap_service() {
    # search for a sql service looking at the label
    jq '[.[][] | select(.credentials.prometheus) ] | first | select (.!=null)' <<<"${VCAP_SERVICES}"
}


reset_env_DB() {
    DB_TYPE="sqlite3"
    DB_USER="root"
    DB_HOST=""
    DB_PASS=""
    DB_PORT=""
    DB_NAME="grafana"
    DB_CA_CERT=""
    DB_CLIENT_CERT=""
    DB_CLIENT_KEY=""
    DB_CERT_NAME=""
    DB_TLS=""
}

set_env_DB() {
    local db="${1}"

    DB_TYPE=$(get_db_vcap_service_type "${db}")
    DB_USER=$(get_db_user "${db}")
    DB_PASS=$(get_db_password "${db}")
    DB_HOST=$(get_db_host "${db}")
    DB_PORT=$(get_db_port "${DB_TYPE}")
    DB_NAME=$(get_db_name "${db}")
    # TLS
    DB_CA_CERT=$(create_ca_cert "${db}" "${DB_NAME}" "${AUTH_ROOT}")
    DB_CLIENT_CERT=$(create_client_cert "${db}" "${DB_NAME}" "${AUTH_ROOT}")
    DB_CLIENT_KEY=$(create_client_key "${db}" "${DB_NAME}" "${AUTH_ROOT}")
    DB_TLS=$(get_db_tls "${db}")
    DB_CERT_NAME=$(get_db_cert_name "${db}")

    echo "${DB_TYPE}://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
}

# Given a DB from vcap services, defines the proxy files ${DB_NAME}-auth.json and
# ${AUTH_ROOT}/${DB_NAME}.proxy
set_DB_proxy() {
    local db="${1}"

    local proxy
    # If it is a google service, setup proxy by creating 2 files: auth.json and
    # cloudsql proxy configuration on ${DB_NAME}.proxy
    # It will also overwrite the variables to point to localhost
    if is_google_service "${db}"; then
        jq -r '.credentials.PrivateKeyData' <<<"${db}" | base64 -d > "${AUTH_ROOT}/${DB_NAME}-auth.json"
        proxy=$(jq -r '.credentials.ProjectId + ":" + .credentials.region + ":" + .credentials.instance_name' <<<"${db}")
        echo "${proxy}=tcp:${DB_PORT}" > "${AUTH_ROOT}/${DB_NAME}.proxy"
        [[ "${DB_TYPE}" == "mysql" ]] && DB_TLS="false"
        [[ "${DB_TYPE}" == "postgres" ]] && DB_TLS="disable"
        DB_HOST="127.0.0.1"
    fi
    echo "${DB_TYPE}://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
}

# Sets all DB
set_sql_databases() {
    local db

    echo "Initializing DB settings from service instances ..."
    reset_env_DB

    db=$(get_db_vcap_service "${VCAP_SERVICES}" "${DB_BINDING_NAME}")
    if [[ -n "${db}" ]]
    then
        set_env_DB "${db}" >/dev/null
        set_DB_proxy "${db}" >/dev/null
    fi
}

# TODO - handle multiple influxdb datasources.
set_vcap_datasource_influxdb() {
  local datasource="${1}"
  local orgId="1"

  local label=$(jq -r '.label' <<<"${datasource}")
  if [[ "${label}" = "csb-aws-influxdb" ]]; then

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

set_seed_secrets() {
    if [[ -z "${SECRET_KEY}" ]]
    then
        # Take it from the space_id. It is not random!
        export SECRET_KEY=$(jq -r '.space_id' <<<"${VCAP_APPLICATION}")
        echo "######################################################################"
        echo "WARNING: SECRET_KEY environment variable not defined!"
        echo "Used for signing some datasource settings like secrets and passwords."
        echo "Cannot be changed without requiring an update to datasource settings to re-encode them."
        echo "Please define it in grafana.ini or using an environment variable!"
        echo "Generated SECRET_KEY=${SECRET_KEY}"
        echo "######################################################################"
    fi
}

install_grafana_plugins() {
    echo "Initializing plugins from ${GRAFANA_CFG_PLUGINS} ..."
    if [[ -f "${GRAFANA_CFG_PLUGINS}" ]]
    then
        while read -r pluginid pluginversion
        do
            if [[ -n "${pluginid}" ]]
            then
                echo "Installing ${pluginid} ${pluginversion} ..."
                grafana-cli --pluginsDir "$GF_PATHS_PLUGINS" plugins install ${pluginid} ${pluginversion}
            fi
        done <<<$(grep -v '^#' "${GRAFANA_CFG_PLUGINS}")
    fi
}

run_sql_proxies() {
    local instance
    local dbname

    if [[ -d ${AUTH_ROOT} ]]
    then
        for filename in $(find ${AUTH_ROOT} -name '*.proxy')
        do
            dbname=$(basename "${filename}" | sed -n 's/^\(.*\)\.proxy$/\1/p')
            instance=$(head "${filename}")
            echo "Launching local sql proxy for instance ${instance} ..."
            launch cloud_sql_proxy -verbose \
                  -instances="${instance}" \
                  -credential_file="${AUTH_ROOT}/${dbname}-auth.json" \
                  -term_timeout=30s -ip_address_types=PRIVATE,PUBLIC
        done
    fi
}

run_grafana_server() {
    echo "Launching grafana server ..."
    pushd "${GRAFANA_ROOT}" >/dev/null
        if [[ -f "${GRAFANA_CFG_INI}" ]]
        then
            launch grafana-server -config=${GRAFANA_CFG_INI}
        else
            launch grafana-server
        fi
    popd
}

set_homedashboard() {
    local dashboard_httpcode=()
    local dashboard_id

    readarray -t dashboard_httpcode <<<$(
        curl -s -w "\n%{response_code}\n" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        "http://127.0.0.1:${PORT}/api/dashboards/uid/${HOME_DASHBOARD_UID}" \
    )
    if [[ "${dashboard_httpcode[1]}" -eq 200 ]]
    then
        dashboard_id=$(jq '.dashboard.id' <<<"${dashboard_httpcode[0]}")
        output=$(curl -s -X PUT -u "${ADMIN_USER}:${ADMIN_PASS}" \
                 -H 'Content-Type: application/json;charset=UTF-8' \
                 -H "X-Grafana-Org-Id: ${HOME_ORG_ID}" \
                 --data-binary "{\"homeDashboardId\": ${dashboard_id}}" \
                 "http://127.0.0.1:${PORT}/api/org/preferences")
        echo "Defined default home dashboard id ${dashboard_id} for org ${HOME_ORG_ID}: ${output}"
    elif [[ "${dashboard_httpcode[1]}" -eq 404 ]]
    then
        echo "No default home dashboard for org ${HOME_ORG_ID} has been found"
    else
        echo "Error setting default HOME dashboard: ${dashboard_httpcode[0]}"
    fi

}

set_users() {
    if [[ -d "${GRAFANA_USER_CONFIG_ROOT}" ]]
    then
        for user_config_file in "${GRAFANA_USER_CONFIG_ROOT}/*.yml"
        do
            for user in  $(yq eval -o=j -I=0 '.users[]' ${user_config_file})
            do
                name=$(eval "echo $(echo $user | jq '.name')")
                login=$(eval "echo $(echo $user | jq '.login')")
                password=$(eval "echo $(echo $user | jq '.password')")
                email=$(eval "echo $(echo $user | jq '.email')")
                orgId=$(eval "echo $(echo $user | jq '.orgId')")
                role=$(eval "echo $(echo $user | jq '.role')")

                echo "Add user - name: ${name}, login: ${login}, email: ${email}, orgId: ${orgId}"
                curl -s -H "Content-Type: application/json" \
                     -u "${ADMIN_USER}:${ADMIN_PASS}" \
                    -XPOST "http://127.0.0.1:${PORT}/api/admin/users" \
                    -d @- <<EOF
{
    "name":"${name}",
    "login":"${login}",
    "password":"${password}",
    "email":"${email}",
    "orgId":${orgId}
}
EOF

                echo "Associate user ${login} with org ${orgId} and role ${role}"
                curl -s -H "Content-Type: application/json" \
                     -u "${ADMIN_USER}:${ADMIN_PASS}" \
                    -XPOST "http://127.0.0.1:${PORT}/api/orgs/${orgId}/users" \
                    -d @- <<EOF
{
    "loginOrEmail":"${login}",
    "role":"${role}"
}
EOF
            done
        done
    fi
}

configure_post_startup() {
    local counter=30
    local status=0

    while [[ ${counter} -gt 0 ]]
    do
        if status=$(curl -s -o /dev/null -w '%{http_code}' \
                -u "${ADMIN_USER}:${ADMIN_PASS}" \
                -H "X-Grafana-Org-Id: ${HOME_ORG_ID}" \
                "http://127.0.0.1:${PORT}/api/org/preferences")
        then
            [[ ${status} -eq 200 ]] && break
        fi
        sleep 2
        counter=$((counter - 1))
    done
    if [[ ${status} -eq 200 ]]
    then
        set_users
        set_homedashboard
    else
        echo "Error setting querying preferences to determine grafana application startup: ${status}"
    fi
}

personalise_public_config() {
  if [[ -d ${APP_ROOT}/public ]]; then
    cp -r ${APP_ROOT}/public ${GRAFANA_ROOT}
  fi
}

################################################################################

personalise_public_config
generate_alerts_from_templates
pre_process ${GRAFANA_DASHBOARD_ROOT}
pre_process ${GRAFANA_ALERTING_ROOT}
set_sql_databases
set_seed_secrets
set_datasources

# Run
install_grafana_plugins
run_sql_proxies
run_grafana_server &
# Set home dashboard only on the first instance
[[ "${CF_INSTANCE_INDEX:-0}" == "0" ]] && configure_post_startup
# Go back to grafana_server and keep waiting, exit whit its exit code
wait

