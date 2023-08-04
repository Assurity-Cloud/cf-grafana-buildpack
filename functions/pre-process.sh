#!/usr/bin/env bash
set -euo pipefail

pre_process() {
  local root_dir="${1}"
  if [[ -d "${root_dir}/pre-process" ]]
  then
      for pre_process_config_file in "${root_dir}/pre-process/*.yml"
      do
          files_to_process=$(yq eval '.files_to_process' ${pre_process_config_file})

          for replacement in $(yq eval -o=j -I=0 '.replacements[]' ${pre_process_config_file})
          do
              find=$(eval "echo $(echo $replacement | jq '.find')")
              replace=$(eval "echo $(echo $replacement | jq '.replace')")

              echo "Finding $find in ${root_dir}/${files_to_process} and replacing with $replace"
              sed_command="s/$find/$replace/g"
              sed -i -- $sed_command ${root_dir}/${files_to_process}
          done
      done
  fi
}