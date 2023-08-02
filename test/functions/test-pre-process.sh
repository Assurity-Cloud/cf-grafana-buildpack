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
  source functions/pre-process.sh
  set +e
}

tearDown() {
  if [[ -d "${ROOT}" ]]; then
    rm -r "${ROOT}"
  fi
}

test_pre_process() {
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

# Run tests by sourcing shunit2
source "${shunit2_location}"