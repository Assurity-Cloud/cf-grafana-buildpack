#!/usr/bin/env bash

shunit2_location=""
shunit2_location="$(which shunit2)" || {
  curl -sLo shunit2 https://raw.githubusercontent.com/kward/shunit2/master/shunit2
  chmod +x shunit2
  shunit2_location=$PWD/shunit2
}

setUp() {
  ROOT=$PWD/tmp
  mkdir -p "${ROOT}/users"
  source functions/post-process.sh
  set +eu
}

tearDown() {
  if [[ -d "${ROOT}" ]]; then
    rm -r "${ROOT}"
  fi
}

curl() {
  while read data; do
    echo "${data}" >> "${ROOT}/sent.json"
  done
}

test_set_users() {
  export BOB_NAME="bob"
  export BOB_PASSWORD="bob1"
  export BOB_EMAIL="bob@bob.com"
  cat <<EOF > ${ROOT}/users/users.yml
users:
  - name: "\${BOB_NAME}"
    login: "\${BOB_NAME}"
    password: "\${BOB_PASSWORD}"
    email: "\${BOB_EMAIL}"
    orgId: 1
    role: "Viewer"
EOF
  read -r -d '' expected_sent_data << EOF
{
"name":"bob",
"login":"bob",
"password":"bob1",
"email":"bob@bob.com",
"orgId":1
}
{
"loginOrEmail":"bob",
"role":"Viewer"
}
EOF

  set_users "${ROOT}/users"
  assertTrue $?
  assertEquals "${expected_sent_data}" "$(cat "${ROOT}/sent.json")"
}

# Run tests by sourcing shunit2
source "${shunit2_location}"