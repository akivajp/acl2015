#!/bin/bash

dir="$(cd "$(dirname "${BASH_SOURCE:-${(%):-%N}}")"; pwd)"
source "${dir}/common.sh"

usage()
{
  echo "usage: $0 mt_method path/to/inifile src_input outdir"
}

if [ ${#ARGS[@]} -lt 4 ]
then
  usage
  exit 1
fi

mt_method=${ARGS[0]}
inifile=${ARGS[1]}
input=${ARGS[2]}
outdir=${ARGS[3]}

show_exec rm -rf ${outdir}
if [ "${mt_method}" == "pbmt" ]; then
  show_exec ${MOSES}/scripts/training/filter-model-given-input.pl ${outdir} ${inifile} ${input} -Binarizer ${BIN}/processPhraseTable
else
  show_exec ${TRAVATAR}/script/train/filter-model.pl ${inifile} ${outdir}/travatar.ini ${outdir} \"${TRAVATAR}/script/train/filter-rule-table.py ${input}\"
fi

