#!/usr/bin/env bash
set -euo pipefail

source functions/base.sh

get_db_vcap_service() {
  local vcap_services="${1}"
  local binding_name="${2:-null}"

  if [[ -z "${binding_name}" ]] || [[ "${binding_name}" == "null" ]]
  then
    jq '[.[][] | select(.credentials.uri) | select(.credentials.uri | split(":")[0] == ("mysql","postgres","postgresql"))] | first | select (.!=null)' <<<"${vcap_services}"
  else
    get_binding_service "${vcap_services}" "${binding_name}"
  fi
}

get_db_vcap_service_type() {
  local db="${1}"
  db_type="$(jq -r -e '.tags[] | select((.=="mysql") or (.=="postgres") or (.=="postgresql"))' <<<"${db}")" ||
    db_type="$(jq -r -e '.credentials.uri | split(":")[0]' <<<"${db}")" ||
    db_type=""

  if [[ $db_type == "postgresql" ]]
  then
    db_type="postgres"
  fi
  echo $db_type
}

get_db_user() {
  local db="${1}"
  db_user=$(jq -r -e '.credentials.Username' <<<"${db}") ||
    db_user=$(jq -r -e '.credentials.username' <<<"${db}") ||
      db_user=$(jq -r -e '.credentials.uri |
          split("://")[1] | split(":")[0]' <<<"${db}") ||
        db_user=''
  echo "${db_user}"
}

get_db_password() {
  local db="${1}"
  db_pass=$(jq -r -e '.credentials.Password' <<<"${db}") ||
    db_pass=$(jq -r -e '.credentials.password' <<<"${db}") ||
      db_pass=$(jq -r -e '.credentials.uri |
          split("://")[1] | split(":")[1] |
          split("@")[0]' <<<"${db}") ||
        db_pass=''

  echo "${db_pass}"
}

get_db_host() {
  local db="${1}"
  db_host=$(jq -r -e '.credentials.host' <<<"${db}") ||
    db_host=$(jq -r -e '.credentials.hostname' <<<"${db}") ||
      db_host=$(jq -r -e '.credentials.uri |
          split("://")[1] | split(":")[1] |
          split("@")[1] |
          split("/")[0]' <<<"${db}") ||
        db_host=$(jq -r -e '.credentials.uri |
            split("://")[1] |
            split("/")[0]' <<<"${db}") ||
          db_host=''
  echo "${db_host}"
}

get_db_name() {
  local db="${1}"
  db_name=$(jq -r -e '.credentials.database_name' <<<"${db}") ||
    db_name=$(jq -r -e '.credentials.database' <<<"${db}") ||
      db_name=$(jq -r -e '.credentials.uri |
          split("://")[1] | split("/")[1] |
          split("?")[0]' <<<"${db}") ||
        db_name=''
  echo "${db_name}"
}

get_db_port() {
  local db_type=${1}
  local db_port=""

  if [[ "${db_type}" == "mysql" ]]
  then
      db_port="3306"
  elif [[ "${db_type}" == "postgres" ]]
  then
      db_port="5432"
  fi

  echo $db_port
}

get_ca_cert() {
  local db="${1}"
  ca_cert="$(jq -r -e '.credentials.CaCert' <<< "${db}")" ||
    ca_cert="$(jq -r -e '.credentials.certificate_authority' <<< "${db}")" ||
    ca_cert=""
  echo "${ca_cert}"
}

get_ca_filename() {
  local db="${1}"
  ca_filename="$(jq -r -e '.credentials.certificate_authority_url | split("/") | last' <<< "${1}")" ||
    ca_filename=""
  echo "${ca_filename}"
}

get_client_cert() {
  local db="${1}"
  client_cert="$(jq -r -e '.credentials.ClientCert' <<< "${1}")" ||
    client_cert=""
  echo "${client_cert}"
}

get_client_key() {
  local db="${1}"
  client_key="$(jq -r -e '.credentials.ClientKey' <<< "${1}")" ||
    client_key=""
  echo "${client_key}"
}

create_ca_cert() {
  local db=${1}
  local db_name=${2}
  local auth_root=${3}
  local db_ca_cert=""
  local cert_val="$(get_ca_cert "${db}")"

  if [[ -n "${cert_val}" ]]
  then
    mkdir -p "${auth_root}"
    local ca_filename="$(get_ca_filename "${db}")"
    if [[ -n "${ca_filename}" ]]; then
      db_ca_cert="${auth_root}/${ca_filename}"
    else
      db_ca_cert="${auth_root}/${db_name}-ca.crt"
    fi
    echo "${cert_val}" > "${db_ca_cert}"
  fi

  echo "${db_ca_cert}"
}

create_client_cert() {

  local db=${1}
  local db_name=${2}
  local auth_root=${3}
  local db_client_cert=""
  local cert_val="$(get_client_cert "${db}")"

  if [[ -n "${cert_val}" ]]
  then
    mkdir -p "${auth_root}"
    db_client_cert="${auth_root}/${db_name}-client.crt"
    echo "${cert_val}" > "${db_client_cert}"
  fi

  echo "${db_client_cert}"
}

create_client_key() {
  local db=${1}
  local db_name=${2}
  local auth_root=${3}
  local db_client_key=""
  local key_val="$(get_client_key "${db}")"

  if [[ -n "${key_val}" ]]
  then
    mkdir -p "${auth_root}"
    db_client_key="${auth_root}/${db_name}-client.key"
    echo "${key_val}" > "${db_client_key}"
  fi

  echo "${db_client_key}"
}

get_db_cert_name() {
  local db=${1}

  db_cert_name="$(jq -r -e '.credentials.instance_name' <<<"${db}")" ||
    db_cert_name="$(jq -r -e '.credentials.hostname' <<<"${db}")" ||
    db_cert_name=""
  project="$(jq -r -e '.credentials.ProjectId' <<<"${db}")" || project=""

  if [[ -n "${db_cert_name}" && -n "${project}" ]]; then
    db_cert_name="${project}:${db_cert_name}"
  fi

  echo "${db_cert_name}"
}

calculate_db_tls() {
  local db_type=${1}
  local cert=${2:-""}
  local db_cert_name=${3:-""}

  if [[ -n "${cert}"  ]]
  then
    if [[ -n "${db_cert_name}" ]]
    then
      [[ "${db_type}" == "mysql" ]] && echo "true"
      [[ "${db_type}" == "postgres" ]] && echo "verify-full"
    else
      [[ "${db_type}" == "mysql" ]] && echo "skip-verify"
      [[ "${db_type}" == "postgres" ]] && echo "require"
    fi
  else
    [[ "${db_type}" == "mysql" ]] && echo "false"
    [[ "${db_type}" == "postgres" ]] && echo "disable"
  fi
}

get_db_tls() {
  local db=${1}
  local db_tls=""

  local db_type="$(get_db_vcap_service_type "${db}")"
  local db_cert_name="$(get_db_cert_name "${db}")"

  if is_google_service "${db}"; then
    local client_cert="$(get_client_cert "${db}")"
    db_tls="$(calculate_db_tls "${db_type}" "${db_cert_name}" "${client_cert}")"

  elif is_aws_service "${db}"; then
    local ca_cert="$(get_ca_cert "${db}")"
    db_tls="$(calculate_db_tls "${db_type}" "${db_cert_name}" "${ca_cert}")"
  fi

  echo "${db_tls}"
}

get_delete_datasources_object() {
  local datasource=${1}
  local orgId=${2}

  databases=$(jq -r '.credentials.bound_databases' <<<"${datasource}")

  jq -r '.[]' <<< "${databases}" | while read -r database; do
    cat <<EOF
- name: ${database}
  orgId: ${orgId}
EOF
  done
}

get_datasources_object() {
  local datasource=${1}
  local orgId=${2}

  binding_name=$(jq -r '.binding_name' <<<"${datasource}")
  databases=$(jq -r '.credentials.bound_databases' <<<"${datasource}")
  url="$(echo ${datasource} | jq -r '.credentials.url')"
  username="$(echo ${datasource} | jq -r '.credentials.username')"
  password="$(echo ${datasource} | jq -r '.credentials.password')"

  jq -r '.[]' <<< "${databases}" | while read -r database; do
    cat <<EOF
- name: ${binding_name}-${database}
  type: influxdb
  access: proxy
  url: ${url}
  database: ${database}
  user: ${username}
  orgId: ${orgId}
  secureJsonData:
    password: ${password}
EOF
  done
}

