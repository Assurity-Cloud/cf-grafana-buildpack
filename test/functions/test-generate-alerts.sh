#!/usr/bin/env bash

shunit2_location=""
shunit2_location="$(which shunit2)" || {
  curl -sLo shunit2 https://raw.githubusercontent.com/kward/shunit2/master/shunit2
  chmod +x shunit2
  shunit2_location=$PWD/shunit2
}

setUp() {
  export GRAFANA_ALERTING_ROOT=$PWD/tmp
  mkdir -p "${GRAFANA_ALERTING_ROOT}"
  source functions/generate-alerts.sh
  set +e
}

tearDown() {
  if [[ -d "${GRAFANA_ALERTING_ROOT}" ]]; then
    rm -r "${GRAFANA_ALERTING_ROOT}"
  fi
}

test_replace_placeholders_with_spaces() {
  local filename="${GRAFANA_ALERTING_ROOT}/changeme.txt"
  echo "Replace+this++with+ a space" > "${filename}"
  replace_placeholders_with_spaces "${filename}"
  assertEquals "Replace this  with  a space" "$(cat "${filename}")"
}

test_replace_headers_with_data() {
  cat <<EOF > ${GRAFANA_ALERTING_ROOT}/data.csv
head1,head2,head3
val1a,val2a,val3a
val1b,val2b,val3b
EOF
  echo "Our values are {head1}, {head2} and {head3}." > "${GRAFANA_ALERTING_ROOT}/changeme1.txt"
  echo "Our values are {head1}, {head2} and {head3}." > "${GRAFANA_ALERTING_ROOT}/changeme2.txt"

  replace_headers_with_data "${GRAFANA_ALERTING_ROOT}/data.csv" "${GRAFANA_ALERTING_ROOT}/changeme1.txt ${GRAFANA_ALERTING_ROOT}/changeme2.txt"

  assertEquals "Our values are val1a, val2a and val3a." "$(cat "${GRAFANA_ALERTING_ROOT}/changeme1.txt")"
  assertEquals "Our values are val1b, val2b and val3b." "$(cat "${GRAFANA_ALERTING_ROOT}/changeme2.txt")"
}

test_generate_alerts_from_templates() {

  mkdir -p "${GRAFANA_ALERTING_ROOT}/templates/threshold"
  cat <<EOF > ${GRAFANA_ALERTING_ROOT}/templates/threshold/group.yml.template
  - orgId: 1
    name: threshold
    rules:
EOF
  cat <<EOF > ${GRAFANA_ALERTING_ROOT}/templates/threshold/rule-threshold.yml.template
      - uid: rule-threshold-{title}
        title: {title} over {threshold_seconds} seconds
EOF
  cat <<EOF > ${GRAFANA_ALERTING_ROOT}/templates/threshold/rule-threshold.csv
title,threshold_seconds
SystemA,5
SystemB,10
SystemC,20
EOF

  generate_alerts_from_templates

  read -r -d '' expected_alerts <<-EOF
apiVersion: 1

groups:
  - orgId: 1
    name: threshold
    rules:

      - uid: rule-threshold-SystemA
        title: SystemA over 5 seconds

      - uid: rule-threshold-SystemB
        title: SystemB over 10 seconds

      - uid: rule-threshold-SystemC
        title: SystemC over 20 seconds
EOF
  assertEquals "${expected_alerts}" "$(cat "${GRAFANA_ALERTING_ROOT}/alert-groups.yml")"
}

# Run tests by sourcing shunit2
source "${shunit2_location}"