
get_binding_service() {
  local vcap_services="${1}"
  local binding_name="${2}"
  jq --arg b "${binding_name}" '.[][] | select(.binding_name == $b)' <<<"${vcap_services}"
}
