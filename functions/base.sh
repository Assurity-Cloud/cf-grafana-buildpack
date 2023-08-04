
get_binding_service() {
  local vcap_services="${1}"
  local binding_name="${2}"
  jq --arg b "${binding_name}" '.[][] | select(.binding_name == $b)' <<<"${vcap_services}"
}

is_google_service() {
  jq -r -e '.tags | contains(["gcp"])' <<<"${1}" >/dev/null
}

is_aws_service() {
  jq -r -e '.tags | contains(["aws"])' <<<"${1}" >/dev/null
}