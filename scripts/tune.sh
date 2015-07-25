#!/bin/bash

dir="$(cd "$(dirname "${BASH_SOURCE:-${(%):-%N}}")"; pwd)"
source "${dir}/common.sh"

TUNE_NBEST=200
EVAL=bleu

usage()
{
  echo "usage: $0 mt_method corpus1 corpus2 inifile task_dir"
  echo ""
  echo "options:"
  echo "  --threads={integer}"
}

if [ ${#ARGS[@]} -lt 5 ]
then
  usage
  exit 1
fi

if [ ${opt_threads} ]; then
  THREADS=${opt_threads}
fi

mt_method=${ARGS[0]}
src1=$(abspath ${ARGS[1]})
src2=$(abspath ${ARGS[2]})
inifile=$(abspath ${ARGS[3]})
task=${ARGS[4]}

workdir="${task}/working"
show_exec mkdir -p ${workdir}
#show_exec rm -rf ${workdir}/mert-work
if [ "${mt_method}" == "pbmt" ]; then
  task=$(abspath $task)
  show_exec pushd ${workdir}
  show_exec $MOSES/scripts/training/mert-moses.pl ${src1} ${src2} ${BIN}/moses ${inifile} --mertdir $MOSES/bin --threads ${THREADS} \> mert.out
  show_exec popd ${workdir}
elif [ "${mt_method}" == "hiero" ]; then
  options=""
  trg_factors=$(grep -1 trg_factors $inifile | tail -n1)
  if [ "${trg_factors}" ]; then
    options="-trg-factors ${trg_factors}"
    if [ ${trg_factors} -gt 1 ]; then
      EVAL="bleu:factor=0"
    fi
  fi
#  show_exec $TRAVATAR/script/mert/mert-travatar.pl -travatar-config ${inifile} -nbest ${TUNE_NBEST} -src ${src1} -ref ${src2} -travatar-dir ${TRAVATAR} -working-dir ${workdir}/mert-work -in-format word -threads ${THREADS} -eval bleu
  show_exec $TRAVATAR/script/mert/mert-travatar.pl -travatar-config ${inifile} -nbest ${TUNE_NBEST} -src ${src1} -ref ${src2} -travatar-dir ${TRAVATAR} -working-dir ${workdir}/mert-work -in-format word -threads ${THREADS} -eval ${EVAL} ${options} -resume
elif [ "${mt_method}" == "t2s" ]; then
  show_exec $TRAVATAR/script/mert/mert-travatar.pl -travatar-config ${inifile} -nbest ${TUNE_NBEST} -src ${src1} -ref ${src2} -travatar-dir ${TRAVATAR} -working-dir ${workdir}/mert-work -in-format penn -threads ${THREADS} -eval ${EVAL} -resume
fi

