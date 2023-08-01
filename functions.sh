#!/usr/bin/env bash
set -euo pipefail


get_binding_service() {
  local vcap_services="${1}"
  local binding_name="${2}"
  jq --arg b "${binding_name}" '.[][] | select(.binding_name == $b)' <<<"${vcap_services}"
}

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
  local db_type=$(jq -r '.credentials.uri | split(":")[0]' <<<"${db}")

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

create_ca_cert() {
  local db=${1}
  local db_name=${2}
  local auth_root=${3}
  local db_ca_cert=""
  local cert_val="$(jq -r '.credentials.CaCert' <<< "${db}")"

  if [[ -n "${cert_val}" && "${cert_val}" != "null" ]]
  then
    mkdir -p "${auth_root}"
    db_ca_cert="${auth_root}/${db_name}-ca.crt"
    echo "${cert_val}" > "${db_ca_cert}"
  fi

  echo "${db_ca_cert}"
}

create_client_cert() {

  local db=${1}
  local db_name=${2}
  local auth_root=${3}
  local db_client_cert=""
  local cert_val="$(jq -r '.credentials.ClientCert' <<< "${db}")"

  if [[ -n "${cert_val}" && "${cert_val}" != "null" ]]
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
  local key_val="$(jq -r '.credentials.ClientKey' <<< "${db}")"

  if [[ -n "${key_val}" && "${key_val}" != "null" ]]
  then
    mkdir -p "${auth_root}"
    db_client_key="${auth_root}/${db_name}-client.key"
    echo "${key_val}" > "${db_client_key}"
  fi

  echo "${db_client_key}"
}