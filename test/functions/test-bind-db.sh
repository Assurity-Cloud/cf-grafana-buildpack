#!/usr/bin/env bash

shunit2_location=""
shunit2_location="$(which shunit2)" || {
  curl -sLo shunit2 https://raw.githubusercontent.com/kward/shunit2/master/shunit2
  chmod +x shunit2
  shunit2_location=$PWD/shunit2
}

setUp() {
  read -r -d '' AURORA_MYSQL <<-EOF
    {
      "binding_guid": "a49fe2e5-3f7a-4d55-94e2-07cd4d345e96",
      "binding_name": "mysql1",
      "credentials": {
        "certificate_authority": "-----BEGIN CERTIFICATE-----Someteststuff-----END CERTIFICATE-----",
        "certificate_authority_url": "https://truststore.pki.rds.amazonaws.com/region/region-bundle.pem",
        "database": "test_db",
        "hostname": "test-db1.test-region.rds.amazonaws.com",
        "jdbcUrl": "jdbc:mysql://test-db1.test-region.rds.amazonaws.com:3306/test_db?user=test-user&password=test-pw&useSSL=true",
        "name": "test_db",
        "password": "test-pw",
        "port": 3306,
        "reader_hostname": "test-db.test-region.rds.amazonaws.com",
        "status": "created db test_db (id: test-db1) on server test-db1.test-region.rds.amazonaws.com",
        "username": "test-user"
      },
      "instance_guid": "374a0f87-9bfe-4358-b74a-d701bd260b0b",
      "instance_name": "test-db1",
      "label": "csb-aws-aurora-mysql",
      "name": "test-db1",
      "plan": "custom",
      "provider": null,
      "syslog_drain_url": null,
      "tags": [
        "aws",
        "aurora",
        "mysql"
      ],
      "volume_mounts": []
    }
EOF
  VCAP_SERVICES="{\"csb-aws-aurora-mysql\": [${AURORA_MYSQL}]}"
  export APP_ROOT=$PWD/tmp
  mkdir -p "${APP_ROOT}"

  source functions/bind-db.sh
  set +e
}

tearDown() {
  if [ -d "${APP_ROOT}" ]; then
    rm -r "${APP_ROOT}"
  fi
}

test_get_db_vcap_service_without_binding_name() {
  read -r -d '' vcap_services <<-EOF
{
  "csb-aws-aurora-mysql": [
    {
      "credentials": {
        "uri": "mysql://test-user:test-pw@test-db1.test-region.rds.amazonaws.com:3306/test_db"
      },
      "instance_name": "test-db1"
    }
  ]
}
EOF
  local service=$(get_db_vcap_service "${vcap_services}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "test-db1" "$(jq -r '.instance_name' <<<$service)"
}

test_get_db_vcap_service_with_binding_name() {
  local service=$(get_db_vcap_service "${VCAP_SERVICES}" mysql1)
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "test-db1" "$(jq -r '.instance_name' <<<$service)"
}

test_get_db_vcap_service_type() {
  read -r -d '' service <<-EOF
{
  "credentials": {
    "uri": "mysql://this.that.org"
  }
}
EOF
  local service_type=$(get_db_vcap_service_type "${service}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "mysql" "${service_type}"
}

test_get_db_vcap_service_type_postgresql_equals_postgres() {
  read -r -d '' service <<-EOF
{
  "credentials": {
    "uri": "postgresql://this.that.org"
  }
}
EOF
  local service_type=$(get_db_vcap_service_type "${service}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "postgres" "${service_type}"
}

test_get_db_user_from_aws_username() {
  local username=$(get_db_user "${AURORA_MYSQL}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "test-user" "${username}"
}

test_get_db_user_from_gcp_username() {
  read -r -d '' service <<-EOF
{
  "credentials": {
    "uri": "mysql://this.that.org",
    "Username": "charlie"
  }
}
EOF
  local username=$(get_db_user "${service}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "charlie" "${username}"
}

test_get_db_user_from_uri() {
  read -r -d '' service <<-EOF
{
  "binding_name": "mysql1",
  "instance_name": "grafana_mysql",
  "credentials": {
    "uri": "mysql://jim:password@this.that.org"
  }
}
EOF
  local username=$(get_db_user "${service}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "jim" "${username}"
}

test_get_db_password_from_aws_password() {
  local password=$(get_db_password "${AURORA_MYSQL}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "test-pw" "${password}"
}

test_get_db_password_from_gcp_password() {
  read -r -d '' service <<-EOF
{
  "credentials": {
    "uri": "mysql://this.that.org",
    "Password": "super-secret"
  }
}
EOF
  local password=$(get_db_password "${service}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "super-secret" "${password}"
}

test_get_db_password_from_uri() {
  read -r -d '' service <<-EOF
{
  "credentials": {
    "uri": "mysql://jim:password@this.that.org"
  }
}
EOF
  local password=$(get_db_password "${service}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "password" "${password}"
}

test_get_db_host_from_aws_host() {
  local db_host=$(get_db_host "${AURORA_MYSQL}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "test-db1.test-region.rds.amazonaws.com" "${db_host}"
}

test_get_db_host_from_gcp_host() {
  read -r -d '' service <<-EOF
{
  "credentials": {
    "uri": "mysql://this.that.org",
    "host": "the.real.host"
  }
}
EOF
  local db_host=$(get_db_host "${service}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "the.real.host" "${db_host}"
}

test_get_db_host_from_uri_with_user_creds() {
  read -r -d '' service <<-EOF
{
  "credentials": {
    "uri": "mysql://jim:password@this.that.org"
  }
}
EOF
  local db_host=$(get_db_host "${service}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "this.that.org" "${db_host}"
}

test_get_db_host_from_uri_without_user_creds() {
  read -r -d '' service <<-EOF
{
  "credentials": {
    "uri": "mysql://this.that.org"
  }
}
EOF
  local db_host=$(get_db_host "${service}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "this.that.org" "${db_host}"
}

test_get_db_name_from_aws_database_name() {
  local db_name=$(get_db_name "${AURORA_MYSQL}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "test_db" "${db_name}"
}

test_get_db_name_from_gcp_database_name() {
  read -r -d '' service <<-EOF
{
  "credentials": {
    "uri": "mysql://this.that.org",
    "database_name": "grafana"
  }
}
EOF
  local db_name=$(get_db_name "${service}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "grafana" "${db_name}"
}

test_get_db_name_from_uri() {
  read -r -d '' service <<-EOF
{
  "credentials": {
    "uri": "mysql://jim:password@this.that.org/db"
  }
}
EOF
  local db_name=$(get_db_name "${service}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "db" "${db_name}"
}

test_get_db_port_mysql() {
  local db_port=$(get_db_port "mysql")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "3306" "${db_port}"
}

test_get_db_port_postgres() {
  local db_port=$(get_db_port "postgres")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "5432" "${db_port}"
}

test_get_ca_filename() {
  local ca_filename=$(get_ca_filename "${AURORA_MYSQL}")
  assertTrue $?
  assertEquals "region-bundle.pem" "${ca_filename}"
}

test_get_ca_filename_no_ca_url() {
  read -r -d '' service <<-EOF
{
  "credentials": {
    "CaCert": "myca"
  }
}
EOF
  local ca_filename=$(get_ca_filename "${service}")
  assertTrue $?
  assertEquals "" "${ca_filename}"
}

test_create_ca_cert_google() {
  read -r -d '' service <<-EOF
{
  "credentials": {
    "CaCert": "myca"
  }
}
EOF
  local key_location=$(create_ca_cert "${service}" mydb "${APP_ROOT}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "${APP_ROOT}/mydb-ca.crt" "${key_location}"
  assertEquals "myca" "$(cat "${key_location}")"
}

test_create_ca_cert_aws() {
  local key_location=$(create_ca_cert "${AURORA_MYSQL}" mydb "${APP_ROOT}")
  assertTrue $?
  assertEquals "${APP_ROOT}/region-bundle.pem" "${key_location}"
  assertEquals "-----BEGIN CERTIFICATE-----Someteststuff-----END CERTIFICATE-----" "$(cat "${key_location}")"
}

test_create_client_cert() {
  read -r -d '' service <<-EOF
{
  "credentials": {
    "ClientCert": "mycert"
  }
}
EOF
  local cert_location=$(create_client_cert "${service}" mydb "${APP_ROOT}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "${APP_ROOT}/mydb-client.crt" "${cert_location}"
  assertEquals "mycert" "$(cat "${cert_location}")"
}

test_create_client_key() {
  read -r -d '' service <<-EOF
{
  "credentials": {
    "ClientKey": "mykey"
  }
}
EOF
  local key_location=$(create_client_key "${service}" mydb "${APP_ROOT}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "${APP_ROOT}/mydb-client.key" "${key_location}"
  assertEquals "mykey" "$(cat "${key_location}")"
}

test_create_client_key_no_value() {
  read -r -d '' service <<-EOF
{
  "credentials": {
    "nothing": "mykey"
  }
}
EOF
  local key_location=$(create_client_key "${service}" mydb "${APP_ROOT}")
  processExitCode=$?
  assertEquals 0 "${processExitCode}"
  assertEquals "" "${key_location}"
}

test_calculate_db_tls_mysql_no_cert() {
  local tls=$(calculate_db_tls "mysql")
  assertTrue $?
  assertEquals "false" "${tls}"
}

test_calculate_db_tls_mysql_with_cert() {
  local tls=$(calculate_db_tls "mysql" "fake-cert-content")
  assertTrue $?
  assertEquals "skip-verify" "${tls}"
}

test_calculate_db_tls_mysql_with_cert_and_hostname() {
  local tls=$(calculate_db_tls "mysql" "fake-cert-content" "host")
  assertTrue $?
  assertEquals "true" "${tls}"
}

test_calculate_db_tls_postgres_no_ca_cert() {
  local tls=$(calculate_db_tls "postgres" "")
  assertTrue $?
  assertEquals "disable" "${tls}"
}

test_calculate_db_tls_postgres_with_ca_cert() {
  local tls=$(calculate_db_tls "postgres" "fake-cert-content")
  assertTrue $?
  assertEquals "require" "${tls}"
}

test_calculate_db_tls_mysql_with_cert_and_hostname() {
  local tls=$(calculate_db_tls "postgres" "fake-cert-content" "host")
  assertTrue $?
  assertEquals "verify-full" "${tls}"
}

test_get_db_tls() {
  local tls=$(get_db_tls "${AURORA_MYSQL}")
  assertTrue $?
  assertEquals "true" "${tls}"
}

test_get_aws_db_cert_name() {
  local db_cert_name=$(get_db_cert_name "${AURORA_MYSQL}")
  assertTrue $?
  assertEquals "test-db1.test-region.rds.amazonaws.com" "${db_cert_name}"
}

test_get_google_cert_name_with_project() {
  read -r -d '' service <<-EOF
{
  "credentials": {
    "instance_name": "instance",
    "ProjectId": "project"
  }
}
EOF
  local db_cert_name=$(get_db_cert_name "${service}")
  assertTrue $?
  assertEquals "project:instance" "${db_cert_name}"
}

test_get_google_cert_name_no_project() {
  read -r -d '' service <<-EOF
{
  "credentials": {
    "instance_name": "instance"
  }
}
EOF
  local db_cert_name=$(get_db_cert_name "${service}")
  assertTrue $?
  assertEquals "instance" "${db_cert_name}"
}

# Run tests by sourcing shunit2
source "${shunit2_location}"
