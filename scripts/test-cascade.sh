#!/bin/bash

dir="$(cd "$(dirname "${BASH_SOURCE:-${(%):-%N}}")"; pwd)"
source "${dir}/common.sh"

usage()
{
  echo "usage: $0 task1 task2 text ref [testname]"
  echo ""
  echo "options:"
  echo "  --threads={integer}"
  echo "  --suffix={string}"
}

if [ ${#ARGS[@]} -lt 4 ]
then
  usage
  exit 1
fi

taskdir1=${ARGS[0]}
taskdir2=${ARGS[1]}
taskname1=$(basename $taskdir1)
taskname2=$(basename $taskdir2)
text=${ARGS[2]}
ref=${ARGS[3]}
testname=${ARGS[4]}
method1=${taskname1%_*}
method2=${taskname2%_*}
lang1=$(expr $taskname1 : ".*_\(..\)" )
lang2=$(expr $taskname1 : ".*_..-\(..\)" )
lang3=$(expr $taskname2 : ".*_..-\(..\)" )

ini1=${taskdir1}/binmodel/moses.ini
ini2=${taskdir2}/binmodel/moses.ini
if [ "$method1" == "hiero" ]; then
#  ini1=${taskdir1}/working/mert-work/travatar.ini
  ini1=${taskdir1}/tuned/travatar.ini
fi
if [ "$method2" == "hiero" ]; then
#  ini2=${taskdir2}/working/mert-work/travatar.ini
  ini2=${taskdir2}/tuned/travatar.ini
fi

echo METHOD1: $method1
echo METHOD2: $method2
echo LANG1: $lang1
echo LANG2: $lang2
echo LANG3: $lang3
echo INI1: $ini1
echo INI2: $ini2

if [ "$method1" = "$method2" ]; then
  workdir="cascade_${method1}_${lang1}-${lang2}-${lang3}"
else
  workdir="cascade_${method1}_${method2}_${lang1}-${lang2}-${lang3}"
fi

if [ "${opt_suffix}" ]; then
  workdir="${workdir}.${opt_suffix}"
fi

ask_continue ${workdir}
show_exec mkdir -p ${workdir}
LOG=${workdir}/log
echo "[${stamp} ${HOST}] $0 $*" >> ${LOG}

target1=${workdir}/translated.${lang2}
if [ "${testname}" ]; then
  target1=${workdir}/translated-${testname}.${lang2}
fi
if [ -f ${target1} ]; then
  echo [skip] translating ${lang1} -> ${lang2}
else
  ${dir}/wait-file.sh ${ini1}
#  if [ "$method1" == "moses" ]; then
  if [ "$method1" == "pbmt" ]; then
    show_exec ${MOSES}/bin/moses -f ${ini1} -threads ${THREADS} \< ${text} \> ${target1}
  elif [ "$method1" == "hiero" ]; then
    show_exec ${TRAVATAR}/script/train/filter-model.pl ${ini1} ${workdir}/${taskname1}/filtered-test.ini ${workdir}/${taskname1}/filtered-test \"${TRAVATAR}/script/train/filter-rule-table.py ${text}\"
#    show_exec ${TRAVATAR}/script/train/filter-model.pl ${ini1} ${workdir}/${taskname1}/filtered-test.ini ${workdir}/${taskname1}/filtered-test \"${TRAVATAR}/script/train/filter-rule-table.py ${text} \| pv\"
#    show_exec ${BIN}/travatar -config_file ${workdir}/${taskname1}/filtered-test.ini -threads ${THREADS} \< ${text} \> ${target1}
    show_exec ${BIN}/travatar -config_file ${workdir}/${taskname1}/filtered-test.ini -threads ${THREADS} \< ${text} \| tee ${target1}
    show_exec rm -rf ${workdir}/${taskname1}
  fi
fi

target2=${workdir}/translated.${lang3}
if [ "${testname}" ]; then
  target2=${workdir}/translated-${testname}.${lang3}
fi
if [ -f ${target2} ]; then
  echo [skip] translating ${lang2} -> ${lang3}
else
  ${dir}/wait-file.sh ${ini2}
#  if [ "$method2" == "moses" ]; then
  if [ "$method2" == "pbmt" ]; then
    show_exec ${MOSES}/bin/moses -f ${ini2} -threads ${THREADS} \< ${target1} \> ${target2}
  elif [ "$method1" == "hiero" ]; then
    show_exec ${TRAVATAR}/script/train/filter-model.pl ${ini2} ${workdir}/${taskname2}/filtered-test.ini ${workdir}/${taskname2}/filtered-test \"${TRAVATAR}/script/train/filter-rule-table.py ${target1}\"
#    show_exec ${TRAVATAR}/script/train/filter-model.pl ${ini2} ${workdir}/${taskname2}/filtered-test.ini ${workdir}/${taskname2}/filtered-test \"${TRAVATAR}/script/train/filter-rule-table.py ${target1} \| pv\"
#    show_exec ${BIN}/travatar -config_file ${workdir}/${taskname2}/filtered-test.ini -threads ${THREADS} \< ${target1} \> ${target2}
    show_exec ${BIN}/travatar -config_file ${workdir}/${taskname2}/filtered-test.ini -threads ${THREADS} \< ${target1} \| tee ${target2}
    show_exec rm -rf ${workdir}/${taskname2}
  fi
fi

score=${workdir}/score.out
if [ "${testname}" ]; then
  score=${workdir}/score-${testname}.out
fi
show_exec ${BIN}/mt-evaluator -ref ${ref} ${target2} \> ${score}
head ${score} | tee -a ${LOG}

echo "##### End of script: $0 $*" | tee -a ${LOG}

