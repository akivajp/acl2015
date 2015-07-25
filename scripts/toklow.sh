#!/bin/bash

dir="$(cd "$(dirname "${BASH_SOURCE:-${(%):-%N}}")"; pwd)"
source "${dir}/common.sh"

usage()
{
  echo "usage: $0 input output"
}

if [ ${#ARGS[@]} -lt 2 ]
then
  usage
  exit 1
fi

input=${ARGS[0]}
output=${ARGS[1]}

show_exec cat ${input} \| ${TRAVATAR}/src/bin/tokenizer \| ${TRAVATAR}/script/tree/lowercase.pl \> ${output}

