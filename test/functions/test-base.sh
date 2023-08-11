#!/usr/bin/env bash

shunit2_location=""
shunit2_location="$(which shunit2)" || {
  curl -sLo shunit2 https://raw.githubusercontent.com/kward/shunit2/master/shunit2
  chmod +x shunit2
  shunit2_location=$PWD/shunit2
}

setUp() {
  source functions/bind-db.sh
  set +e
}

test_get_binding_service() {
  read -r -d '' vcap_services <<-EOF
{
  "csb-aws-aurora-mysql":[
    {
      "binding_name": "mysql1",
      "instance_name": "test-mysql"
    }
  ],
  "csb-aws-influxdb":[
    {
      "binding_name": "influxdb1",
      "instance_name": "test-influxdb-1"
    },
    {
      "binding_name": "influxdb2",
      "instance_name": "test-influxdb-2"
    }
  ]
}
EOF
  local serviceInstanceOne=$(get_binding_service "${vcap_services}" influxdb1)
  processExitCode=$?
  assertEquals 0 "${processExitCode}"

  local serviceInstanceTwo=$(get_binding_service "${vcap_services}" influxdb2)
  processExitCode=$?
  assertEquals 0 "${processExitCode}"

  assertEquals "test-influxdb-1" "$(jq -r '.instance_name' <<<$serviceInstanceOne)"
  assertEquals "test-influxdb-2" "$(jq -r '.instance_name' <<<$serviceInstanceTwo)"
}

test_is_aws_service_positive() {
  read -r -d '' aurora_mysql <<-EOF
    {
      "tags": [
        "aws",
        "aurora",
        "mysql"
      ]
    }
EOF
  is_aws_service "${aurora_mysql}"
  assertTrue $?
}

test_is_aws_service_negative() {
  read -r -d '' gcp_mysql <<-EOF
    {
      "tags": [
        "gcp",
        "mysql"
      ]
    }
EOF
  is_aws_service "${gcp_mysql}"
  assertFalse $?
}

test_is_google_service_positive() {
  read -r -d '' gcp_mysql <<-EOF
    {
      "tags": [
        "gcp",
        "mysql"
      ]
    }
EOF
  is_google_service "${gcp_mysql}"
  assertTrue $?
}

test_is_google_service_negative() {
  read -r -d '' aurora_mysql <<-EOF
    {
      "tags": [
        "aws",
        "aurora",
        "mysql"
      ]
    }
EOF
  is_google_service "${aurora_mysql}"
  assertFalse $?
}

# Run tests by sourcing shunit2
source "${shunit2_location}"