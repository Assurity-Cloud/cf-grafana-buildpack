#!/usr/bin/env bash
set -euo pipefail

run_scripts() {
  local root_dir="${1}"
  if [[ -d "${root_dir}/scripts" ]]
  then
    pushd ${root_dir}/scripts
      for script in *.sh
      do
        if [[ -f $script ]]; then
          source "${script}"
        fi
      done
    popd
  fi
}

pre_process() {
  local root_dir="${1}"
  run_scripts "${root_dir}"
  if [[ -d "${root_dir}/pre-process" ]]
  then
    pushd ${root_dir}/pre-process
      for pre_process_config_file in *.yml
      do
        if [[ -f $pre_process_config_file ]]; then
          files_to_process=$(yq eval '.files_to_process' ${pre_process_config_file})

          for replacement in $(yq eval -o=j -I=0 '.replacements[]' ${pre_process_config_file})
          do
              find=$(eval "echo $(echo $replacement | jq '.find')")
              replace=$(eval "echo $(echo $replacement | jq '.replace')")

              echo "Finding $find in ${root_dir}/${files_to_process} and replacing with $replace"
              sed_command="s/$find/$replace/g"
              sed -i -- $sed_command ${root_dir}/${files_to_process}
          done
        fi
      done
    popd
  fi
}