#!/usr/bin/env bash

shunit2_location=""
shunit2_location="$(which shunit2)" || {
  curl -sLo shunit2 https://raw.githubusercontent.com/kward/shunit2/master/shunit2
  chmod +x shunit2
  shunit2_location=$PWD/shunit2
}

setUp() {
  read -r -d '' INFLUXDB <<-EOF
    {
      "label": "csb-aws-influxdb",
      "provider": null,
      "plan": "default",
      "name": "influxdb1",
      "tags": [
        "aws",
        "influxdb",
        "preview"
      ],
      "instance_guid": "22f79fd5-4e7d-4b4e-9a16-51e89e1f0ba0",
      "instance_name": "test-influxdb-1",
      "binding_guid": "4f7010ff-d6b5-4d50-8810-36d518616c87",
      "binding_name": "influxdb1",
      "credentials": {
        "admin_password": "REDACTED",
        "admin_username": "REDACTED",
        "bound_databases": "[\"dbOne\", \"dbTwo\"]",
        "databases": "[\"dbOne\", \"dbTwo\"]",
        "default_database": "dbOne",
        "hostname": "test-influxdb1.csb.service",
        "password": "test_pw1",
        "port": 443,
        "protocol": "HTTPS",
        "retention_policies": "{}",
        "url": "HTTPS://test-influxdb1.csb.service:443",
        "username": "test_user_1"
      },
      "syslog_drain_url": null,
      "volume_mounts": []
    },
    {
      "label": "csb-aws-influxdb",
      "provider": null,
      "plan": "default",
      "name": "influxdb2",
      "tags": [
        "aws",
        "influxdb",
        "preview"
      ],
      "instance_guid": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
      "instance_name": "test-influxdb-2",
      "binding_guid": "1a5e9f43-2d9e-4b31-b72f-6b2c8b05e8d0",
      "binding_name": "influxdb2",
      "credentials": {
        "admin_password": "REDACTED",
        "admin_username": "REDACTED",
        "bound_databases": "[\"dbThree\", \"dbFour\"]",
        "databases": "[\"dbThree\", \"dbFour\"]",
        "default_database": "dbThree",
        "hostname": "test-influxdb2.csb.service",
        "password": "test_pw2",
        "port": 443,
        "protocol": "HTTPS",
        "retention_policies": "{}",
        "url": "HTTPS://test-influxdb2.csb.service:443",
        "username": "test_user_2"
      },
      "syslog_drain_url": null,
      "volume_mounts": []
    }
EOF
  VCAP_SERVICES="{\"csb-aws-influxdb\": [${INFLUXDB}]}"

  read -r -d '' expected_datasource_config << EOF
apiVersion: 1

deleteDatasources:
- name: "dbOne"
  orgId: 1
- name: "dbTwo"
  orgId: 1

datasources:
- name: "dbOne"
  type: influxdb
  access: proxy
  url: "HTTPS://test-influxdb1.csb.service:443"
  database: "dbOne"
  user: "test_user_1"
  orgId: 1
  readOnly: false
  editable: true
  secureJsonData:
    password: "test_pw1"
- name: "dbTwo"
  type: influxdb
  access: proxy
  url: "HTTPS://test-influxdb1.csb.service:443"
  database: "dbTwo"
  user: "test_user_1"
  orgId: 1
  readOnly: false
  editable: true
  secureJsonData:
    password: "test_pw1"
EOF
  export EXPECTED_DATASOURCE_CONFIG="${expected_datasource_config}"
  export APP_ROOT=$PWD/tmp
  mkdir -p "${APP_ROOT}"

  source functions/bind-data-source.sh
  set +e
}

tearDown() {
  if [ -d "${APP_ROOT}" ]; then
    rm -r "${APP_ROOT}"
  fi
}

test_get_delete_datasources_object() {
  datasource_binding="influxdb1"
  influxdb_datasource=$(get_binding_service "${VCAP_SERVICES}" "${datasource_binding}")

  read -r -d '' expected_delete_datasources <<-EOF
- name: "dbOne"
  orgId: 1
- name: "dbTwo"
  orgId: 1
EOF

  actual_delete_datasources=$(get_delete_datasources_object "${influxdb_datasource}" "1")
  assertTrue $?
  assertEquals "${expected_delete_datasources}" "${actual_delete_datasources}"
}


test_get_datasources_object() {
  datasource_binding="influxdb1"
  influxdb_datasource=$(get_binding_service "${VCAP_SERVICES}" "${datasource_binding}")

  name="$(echo ${influxdb_datasource} | jq -r '.name')"
  expected_url="$(echo ${influxdb_datasource} | jq -r '.credentials.url')"
  expected_username="$(echo ${influxdb_datasource} | jq -r '.credentials.username')"
  expected_password="$(echo ${influxdb_datasource} | jq -r '.credentials.password')"

  read -r -d '' expected_datasources <<-EOF
- name: "dbOne"
  type: influxdb
  access: proxy
  url: "${expected_url}"
  database: "dbOne"
  user: "${expected_username}"
  orgId: 1
  readOnly: false
  editable: true
  secureJsonData:
    password: "${expected_password}"
- name: "dbTwo"
  type: influxdb
  access: proxy
  url: "${expected_url}"
  database: "dbTwo"
  user: "${expected_username}"
  orgId: 1
  readOnly: false
  editable: true
  secureJsonData:
    password: "${expected_password}"
EOF

  actual_datasources=$(get_datasources_object "${influxdb_datasource}" "1")
  assertTrue $?
  assertEquals "${expected_datasources}" "${actual_datasources}"
}

test_set_datasources_without_binding_name() {
  export DATASOURCE_BINDING_NAMES=""
  set_datasources
  assertTrue $?
  assertEquals "${EXPECTED_DATASOURCE_CONFIG}" "$(cat "${APP_ROOT}/datasources/influxdb1.yml")"
}

test_set_datasources_with_binding_name() {
  export DATASOURCE_BINDING_NAMES="influxdb1"
  set_datasources
  assertTrue $?
  assertEquals "${EXPECTED_DATASOURCE_CONFIG}" "$(cat "${APP_ROOT}/datasources/influxdb1.yml")"
}

# Run tests by sourcing shunit2
source "${shunit2_location}"