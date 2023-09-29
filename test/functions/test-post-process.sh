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
  set +e
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
  cat <<EOF > ${ROOT}/users/users.yml
users:
  - name: "bob"
    login: "bobby"
    password: "bob1"
    email: "bob@bob.com"
    orgId: 1
    role: "Viewer"
EOF

  set_users "${ROOT}/users"
  read -r -d '' expected_sent_data << EOF
{
"name":"bob",
"login":"bobby",
"password":"bob1",
"email":"bob@bob.com",
"orgId":1
}
{
"loginOrEmail":"bobby",
"role":"Viewer"
}
EOF
  assertEquals "${expected_sent_data}" "$(cat "${ROOT}/sent.json")"
}

# Run tests by sourcing shunit2
source "${shunit2_location}"