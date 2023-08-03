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
  db_type=$(jq -r -e '.tags[] | select((.=="mysql") or (.=="postgres") or (.=="postgresql"))' <<<"${db}") ||
    db_type=$(jq -r '.credentials.uri | split(":")[0]' <<<"${db}")

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
  echo "$(jq -r '.credentials.CaCert' <<< "${1}")"
}

get_client_cert() {
  echo "$(jq -r '.credentials.ClientCert' <<< "${1}")"
}

get_client_key() {
  echo "$(jq -r '.credentials.ClientKey' <<< "${1}")"
}

create_ca_cert() {
  local db=${1}
  local db_name=${2}
  local auth_root=${3}
  local db_ca_cert=""
  local cert_val="$(get_ca_cert "${db}")"

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
  local cert_val="$(get_client_cert "${db}")"

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
  local key_val="$(get_client_key "${db}")"

  if [[ -n "${key_val}" && "${key_val}" != "null" ]]
  then
    mkdir -p "${auth_root}"
    db_client_key="${auth_root}/${db_name}-client.key"
    echo "${key_val}" > "${db_client_key}"
  fi

  echo "${db_client_key}"
}

get_aws_db_tls() {
  local db_type=${1}
  local db_ca_cert=${2:-""}

  if [[ -n "${db_ca_cert}" && "${db_ca_cert}" != "null" ]]
  then
      [[ "${db_type}" == "mysql" ]] && echo "true"
      [[ "${db_type}" == "postgres" ]] && echo "verify-full"
  else
      [[ "${db_type}" == "mysql" ]] && echo "skip-verify"
      [[ "${db_type}" == "postgres" ]] && echo "require"
  fi
}

get_google_db_tls() {
  local db=${1}
  local db_type=${2}
  local db_client_cert=${3}

  if [[ -n "${db_client_cert}" && "${db_client_cert}" != "null"  ]]
  then
    if instance=$(jq -r -e '.credentials.instance_name' <<<"${db}")
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

get_google_db_cert_name() {
  local db=${1}
  local db_client_cert=${2}
  local db_cert_name=""

  if [[ -n "${db_client_cert}" && "${db_client_cert}" != "null" ]]
  then
    if instance=$(jq -r -e '.credentials.instance_name' <<<"${db}")
    then
      db_cert_name="${instance}"
      if project=$(jq -r -e '.credentials.ProjectId' <<<"${db}")
      then
        # Google GCP format
        db_cert_name="${project}:${instance}"
      fi
    fi
  fi

  echo "${db_cert_name}"
}

get_db_tls() {
  local db=${1}
  local db_tls=""

  local db_type="$(get_db_vcap_service_type "${db}")"

  if is_google_service "${db}"; then
    local client_cert="$(get_client_cert "${db}")"
    db_tls="$(get_google_db_tls "${db}" "${db_type}" "${client_cert}")"

  elif is_aws_service "${db}"; then
    local ca_cert="$(get_ca_cert "${db}")"
    db_tls="$(get_aws_db_tls "${db_type}" "${ca_cert}")"
  fi

  echo "${db_tls}"
}


get_db_cert_name() {
  local db=${1}
  local db_cert_name=""

  if is_google_service "${db}"; then
    db_cert_name="$(get_google_db_cert_name "${db}" "$(get_client_cert "${db}")")"
  fi

  echo "${db_cert_name}"
}