
send_user_config_to_grafana() {
    name=${1}
    login=${2}
    password=${3}
    email=${4}
    orgId=${5}
    role=${6}

    echo "Add user - name: ${name}, login: ${login}, email: ${email}, orgId: ${orgId}"

    curl -s -H "Content-Type: application/json" \
         -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -XPOST "http://127.0.0.1:${PORT}/api/admin/users" \
        -d @- <<EOF
{
    "name":"${name}",
    "login":"${login}",
    "password":"${password}",
    "email":"${email}",
    "orgId":${orgId}
}
EOF

    echo "Associate user ${login} with org ${orgId} and role ${role}"
    curl -s -H "Content-Type: application/json" \
         -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -XPOST "http://127.0.0.1:${PORT}/api/orgs/${orgId}/users" \
        -d @- <<EOF
{
    "loginOrEmail":"${login}",
    "role":"${role}"
}
EOF

}

set_users() {
  local root_dir="${1}"
  if [[ -d "${root_dir}" ]]
  then
    pushd ${root_dir}
      for user_config_file in *.yml
      do
        if [[ -f $user_config_file ]]; then
          for user in  $(yq eval -o=j -I=0 '.users[]' ${user_config_file})
          do
            name=$(eval "echo $(echo $user | jq '.name')")
            login=$(eval "echo $(echo $user | jq '.login')")
            password=$(eval "echo $(echo $user | jq '.password')")
            email=$(eval "echo $(echo $user | jq '.email')")
            orgId=$(eval "echo $(echo $user | jq '.orgId')")
            role=$(eval "echo $(echo $user | jq '.role')")

            send_user_config_to_grafana "${name}" "${login}" "${password}" "${email}" "${orgId}" "${role}"
          done
        fi
      done
    popd
  fi
}
