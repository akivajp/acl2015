#!/bin/bash

dir="$(cd "$(dirname "${BASH_SOURCE:-${(%):-%N}}")"; pwd)"
source "${dir}/common.sh"

usage()
{
  echo "usage: $0 task"
}

if [[ ${#ARGS[@]} -lt 1 ]]; then
  usage
  exit 1
fi

task=${ARGS[0]}

if [[ ! -d ${task} ]]; then
  echo "Task dir is not found: ${task}"
  exit 1
fi

LOG=${task}/log
init_cmd=$(head -1 $LOG | sed -e 's/\[.*\] //')
show_exec ${init_cmd}

