#!/usr/bin/env bash
set -euo pipefail

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
        set -x # FIXME
        echo "$SHELL"
        bash --version
        echo "root_dir is ${root_dir}"
        echo "user_config_file is ${user_config_file}"
        yq --version
        pwd
        echo  "running yq eval test..."
        yq eval -o=json -I=0 '.users[]' "${user_config_file}"
        echo  "end of yq eval test..."
        echo "IFS is... ${IFS}"
        echo "$IFS" | cat -et

        if [[ -f "${user_config_file}" ]]; then
          for user in $(yq eval -o=json -I=0 '.users[]' "${user_config_file}")
          do
            echo "User: $user"
            name=$(eval "echo $(jq '.name' <<< "${user}")")
            login=$(eval "echo $(jq '.login' <<< "${user}")")
            password=$(eval "echo $(jq '.password' <<< "${user}")")
            email=$(eval "echo $(jq '.email' <<< "${user}")")
            orgId=$(eval "echo $(jq '.orgId' <<< "${user}")")
            role=$(eval "echo $(jq '.role' <<< "${user}")")
            send_user_config_to_grafana "${name}" "${login}" "${password}" "${email}" "${orgId}" "${role}"
          done
        fi
        set +x # FIXME
      done
    popd
  fi
}
