#!/bin/bash

dir="$(cd "$(dirname "${BASH_SOURCE:-${(%):-%N}}")"; pwd)"
source "${dir}/common.sh"

echo "running script with PID: $$"

usage()
{
  echo "usage: $0 task_src suffix_trg"
}

if [[ ${#ARGS[@]} -lt 2 ]]; then
  usage
  exit 1
fi

#task_src=$(basename ${ARGS[0]})
task_src=${ARGS[0]}
suffix_trg=${ARGS[1]}

suffix_trg=${suffix_trg#.}
#task_trg="${task_src}.${suffix_trg}"
task_trg="$(basename ${task_src}).${suffix_trg}"

if [ -d ${task_trg} ]; then
  echo "directory \"${task_trg}\" is already found"
  exit 1
fi

if [[ -f "${task_src}/TM/model/moses.ini" ]]; then
  ini="${task_trg}/TM/model/moses.ini"
  decoder="moses"
elif [[ -f "${task_src}/TM/model/travatar.ini" ]]; then
  ini="${task_trg}/TM/model/travatar.ini"
  decoder="travatar"
else
  echo "\"${task_src}\" is not regular task directory"
  echo "Setting file is not found: ${task_src}/TM/model/\{moses,travatar\}.ini"
  exit 1
fi
log="${task_trg}/log"

show_exec rsync -av --link-dest=$(abspath $task_src) $task_src/ ${task_trg}

show_exec mv ${ini} ${ini}.old
#show_exec cat ${ini}.old \| sed -e "'s/${task_src}/${task_trg}/g'" \> ${ini}
show_exec cat ${ini}.old \| sed -e "'s:${task_src}:${task_trg}:g'" \> ${ini}

show_exec mv ${log} ${log}.old
init_cmd=$(head -1 ${log}.old | sed 's/\[.*\] //')
if (echo $init_cmd | grep ' --suffix' > /dev/null); then
  init_cmd=$(echo $init_cmd | sed -e "s/--suffix=\\([^ ]*\\)/--suffix=\\1.${suffix_trg}/")
else
  init_cmd="${init_cmd} --suffix=${suffix_trg}"
fi
show_exec echo "[INIT] ${init_cmd}" \> ${log}

