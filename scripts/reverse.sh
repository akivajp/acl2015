#!/bin/bash

dir="$(cd "$(dirname "${BASH_SOURCE:-${(%):-%N}}")"; pwd)"
source "${dir}/common.sh"

echo "running script with PID: $$"

usage()
{
  echo "usage: $0 t2s_task"
  echo ""
  echo "options:"
  echo "  --threads={int}"
}

src_task=${ARGS[0]}

if [ ${#ARGS[@]} -lt 1 ]; then
  usage
  exit 1
fi

src_taskname=$(basename $src_task)
src_mt_method=$(expr $src_taskname : '\(.*\)_..-..')
src_lang1=$(expr $src_taskname : '.*_\(..\)-..')
src_lang2=$(expr $src_taskname : '.*_..-\(..\)')

if [ "${src_mt_method}" != "t2s" ]; then
  echo "mt_method should be t2s (get '${src_mt_method}')"
  exit 1
fi

lang1=${src_lang2}
lang2=${src_lang1}
task="s2t_${lang1}-${lang2}"

corpus="${task}/corpus"
langdir="${task}/LM_${lang2}"
transdir="${task}/TM"
workdir="${task}/working"
filterdir="${workdir}/filtered"

decoder=travatar
src_test=${corpus}/test.true.${lang1}
src_dev=${corpus}/dev.true.${lang1}
trg_test=${corpus}/test.true.${lang2}
trg_dev=${corpus}/dev.true.${lang2}

tunedir=${task}/tuned
plain_ini=${transdir}/model/travatar.ini
final_ini=${tunedir}/travatar.ini
filtered_ini=${filterdir}/travatar.ini

show_exec mkdir -p ${task}
show_exec mkdir -p ${workdir}
echo "[${stamp} ${HOST}] $0 $*" >> ${task}/log

# -- CORPUS COPYING --
show_exec mkdir -p ${corpus}
show_exec cp ${src_task}/corpus/train.true.${lang2} ${corpus}
show_exec cp ${src_task}/corpus/test.true.{$lang1,$lang2} ${corpus}
show_exec cp ${src_task}/corpus/test.tree.${lang2} ${corpus}
show_exec cp ${src_task}/corpus/dev.true.{$lang1,$lang2} ${corpus}
show_exec cp ${src_task}/corpus/dev.tree.${lang2} ${corpus}

# -- LANGUAGER MODELING --
if [ -f ${langdir}/train.blm.${lang2} ]; then
  echo [autoskip] language modeling
else
  show_exec "${dir}/train-lm.sh" ${lang2} ${corpus}/train.true.${lang2} --task_name=${task}
fi

# -- REVERSING --
if [ -f "${plain_ini}" ]; then
  echo [autoskip] translation model
else
  show_exec mkdir -p ${transdir}/model
  show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/ruletable/reverse.py ${src_task}/TM/model/rule-table.gz ${transdir}/model/rule-table.gz
  show_exec sed -e "s/${src_task}/${task}/g" ${src_task}/TM/model/travatar.ini \> ${plain_ini}
fi

