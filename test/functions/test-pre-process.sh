#!/usr/bin/env bash

shunit2_location=""
shunit2_location="$(which shunit2)" || {
  curl -sLo shunit2 https://raw.githubusercontent.com/kward/shunit2/master/shunit2
  chmod +x shunit2
  shunit2_location=$PWD/shunit2
}

setUp() {
  ROOT=$PWD/tmp
  mkdir -p "${ROOT}/pre-process"
  mkdir -p "${ROOT}/scripts"
  source functions/pre-process.sh
  set +e
}

tearDown() {
  if [[ -d "${ROOT}" ]]; then
    rm -r "${ROOT}"
  fi
}

test_pre_process_finds_and_replaces() {
  cat <<EOF > ${ROOT}/pre-process/config.yml
files_to_process: "*.txt"

replacements:
- find: "{placeholder}"
  replace: "value"
EOF
  echo "This is the {placeholder}." > "${ROOT}/changeme.txt"
  pre_process ${ROOT}
  assertEquals "This is the value." "$(cat "${ROOT}/changeme.txt")"
}

test_pre_process_runs_script() {
  cat <<EOF > ${ROOT}/scripts/test.sh
echo "Test success" > "${ROOT}/test.txt"
EOF
  chmod 755 ${ROOT}/scripts/test.sh
  pre_process ${ROOT}
  assertEquals "Test success" "$(cat "${ROOT}/test.txt")"
}

# Run tests by sourcing shunit2
source "${shunit2_location}"