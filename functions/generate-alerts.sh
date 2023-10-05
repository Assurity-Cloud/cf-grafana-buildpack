#!/usr/bin/env bash
set -euo pipefail

: ${GRAFANA_ALERTING_ROOT:?required}

replace_placeholders_with_spaces() {
  for filename in $1; do
    sed -i -- 's/+/ /g' "${filename}"
  done
}

replace_token_with_data() {
  token=$1
  data_pos=$2
  data_file=$3
  files_to_change=$4

  replace_commands=$(cat ${data_file} | tail -n +2 | awk -F "," "{ print \"s/{${token}}/\" \$${data_pos} \"/g\"}")

  replace_command_array=($replace_commands)
  filename_array=($files_to_change)
  filename_length=${#filename_array[@]}

  for (( pos=0; pos<filename_length; pos++ )); do
    filename="${filename_array[$pos]}"
    replace_command="${replace_command_array[$pos]}"
    echo "replace_command=${replace_command}, filename=${filename}"
    sed -i -- "${replace_command}" "${filename}"
  done
}

replace_headers_with_data() {
  data_file=$1
  files_to_change=$2

  headers=$(head -n 1 ${data_file})
  IFS=$','; header_array=($headers); unset IFS;
  header_length=${#header_array[@]}

  for (( header_pos=0; header_pos<header_length; header_pos++ )); do
    header="${header_array[$header_pos]}"
    echo "header=${header}"
    replace_token_with_data "${header}" $((header_pos + 1)) "${data_file}" "${files_to_change}"
  done
}

merge_alert_template_files() {
  base_file=$1
  for filename in $2; do
    echo '' >> "$base_file"
    cat "$filename" >> "$base_file"
    rm "$filename"
    if [[ -f "${filename}--" ]]; then rm "${filename}--"; fi
  done
}

generate_alerts_from_templates() {
  template_dir=${GRAFANA_ALERTING_ROOT}/templates
  if [[ -d ${template_dir} ]]; then

    alert_groups_filename=${GRAFANA_ALERTING_ROOT}/alert-groups.yml
    cat > ${alert_groups_filename} << EOF
apiVersion: 1

groups:
EOF

    pushd "${template_dir}"

      for subdirectory in */; do

        pushd "${subdirectory}"

          if [ -f "group.yml.template" ]; then
            cat "group.yml.template" >> ${alert_groups_filename}
          fi

          for template in rule-*.yml.template; do

            alert_name="${template%.yml.template}"
            alert_data_file="${alert_name}.csv"

            if [ -f "$alert_data_file" ]; then
              echo "creating alerts from template ${template} with data from ${alert_data_file}"

              filenames=$(cat ${alert_data_file} | tail -n +2 | awk -F "," "{ print \"${GRAFANA_ALERTING_ROOT}/\" \$1 \"-${alert_name}.yml\" }")
              for filename in $filenames; do
                echo "creating alert file ${filename}"
                cp "${template}" "${filename}"
              done

              replace_headers_with_data "${alert_data_file}" "${filenames}"
              replace_placeholders_with_spaces "${filenames}"
              merge_alert_template_files "${alert_groups_filename}" "${filenames}"

            fi

          done
        popd
      done

    popd

    fi
}
