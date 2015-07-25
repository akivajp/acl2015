#!/bin/bash

THREADS=8

NBEST=20

METHOD="counts"

dir="$(cd "$(dirname "${BASH_SOURCE:-${(%):-%N}}")"; pwd)"
source "${dir}/common.sh"


echo "running script with PID: $$"

usage()
{
  echo "usage: $0 lang1 lang2 task1 task2 corpus_dir"
  echo ""
  echo "options:"
  echo "  --overwrite"
  echo "  --task_name={string}"
  echo "  --suffix{string}"
  echo "  --threads={integer}"
  echo "  --skip_integrate"
  echo "  --skip_tuning"
  echo "  --skip_test"
  echo "  --nbest={integer}"
}

if [ ${#ARGS[@]} -lt 5 ]
then
  usage
  exit 1
fi

lang1=${ARGS[0]}
lang2=${ARGS[1]}
task1=${ARGS[2]}
task2=${ARGS[3]}
taskname1=$(basename $task1)
taskname2=$(basename $task2)
corpus_src=${ARGS[4]}

if [ $opt_task_name ]; then
  task=$opt_task_name
else
  task="integrate_moses_${lang1}-${lang2}"
fi

if [ "$opt_suffix" ]; then
  task="${task}${opt_suffix}"
fi

if [ ${opt_threads} ]; then
  THREADS=${opt_threads}
fi

show_exec mkdir -p ${task}
echo "[${stamp} ${HOST}] $0 $*" >> ${task}/log

corpus="${task}/corpus"
langdir=${task}/LM_${lang2}
workdir="${task}/working"
transdir=${task}/TM
show_exec mkdir -p ${workdir}

if [ $opt_skip_integrate ]; then
  echo [skip] integrate
elif [ ! $opt_overwrite ] && [ -f ${transdir}/model/moses.ini ]; then
  echo [autoskip] integrate 
else
  show_exec mkdir -p ${transdir}/model
  ${dir}/wait-file.sh ${task1}/TM/model/moses.ini
  ${dir}/wait-file.sh ${task2}/TM/model/moses.ini

  # COPYING CORPUS
  show_exec mkdir -p ${corpus}
  show_exec cp ${corpus_src}/devtest.true.{${lang1},${lang2}} ${corpus}
  show_exec cp ${corpus_src}/test.true.{${lang1},${lang2}} ${corpus}
  show_exec cp ${corpus_src}/dev.true.{${lang1},${lang2}} ${corpus}

  # COPYING LM
  show_exec mkdir -p ${langdir}
  show_exec cp ${task1}/LM_${lang2}/train.blm.${lang2} ${langdir}

  lexfile="${transdir}/model/lex_${lang1}-${lang2}"
  if [ -f "${lexfile}" ]; then
    echo [skip] calc lex probs
  else
    # 共起回数ピボットの場合、事前に語彙翻訳確率の算出が必要
    lexfile1="${task1}/TM/model/lex_${lang1}-${lang2}"
    lexfile2="${task2}/TM/model/lex_${lang1}-${lang2}"
    if [ -f "${lexfile1}" ]; then
      cp ${lexfile1} ${workdir}/lex1
    else
      show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/align2lex.py ${task1}/corpus/train.clean.{$lang1,$lang2} ${task1}/TM/model/aligned.grow-diag-final-and ${workdir}/lex1
    fi
    if [ -f "${lexfile2}" ]; then
      cp ${lexfile2} ${workdir}/lex2
    else
      show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/align2lex.py ${task2}/corpus/train.clean.{$lang1,$lang2} ${task2}/TM/model/aligned.grow-diag-final-and ${workdir}/lex2
    fi
#    show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/pivot_lex.py ${workdir}/lex1 ${workdir}/lex2 ${lexfile}
    show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/combine_lex.py ${workdir}/lex1 ${workdir}/lex2 ${lexfile}
  fi
  # PIVOTING
  options="--workdir ${workdir}"
  if [ "${THRESHOLD}" ]; then
    options="${options} --threshold ${THRESHOLD}"
  fi
  if [ "${opt_nbest}" ]; then
    options="${options} --nbest ${opt_nbest}"
  else
    options="${options} --nbest ${NBEST}"
  fi
  show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/integrate.py ${task1}/TM/model/phrase-table.gz ${task2}/TM/model/phrase-table.gz ${lexfile} ${transdir}/model/phrase-table.gz ${options}
  show_exec sed -e "s/${task1}/${task}/g" ${task1}/TM/model/moses.ini \> ${transdir}/model/moses.ini
  show_exec rm -rf ${workdir}/integrate
fi

bindir=${task}/binmodel
# -- TUNING --
if [ ! $opt_overwrite ] && [ -f ${bindir}/moses.ini ]; then
  echo [autoskip] tuning
elif [ $opt_skip_tuning ]; then
  echo [skip] tuning
else
#if [ $opt_tuning ]; then
  show_exec ${dir}/tune-moses.sh ${corpus}/dev.true.${lang1} ${corpus}/dev.true.${lang2} ${transdir}/model/moses.ini ${task} --threads=${THREADS}

  # -- BINARIZING --
  show_exec mkdir -p ${bindir}
  show_exec ${BIN}/processPhraseTable -ttable 0 0 ${transdir}/model/phrase-table.gz -nscores 5 -out ${bindir}/phrase-table
  show_exec sed -e "s/PhraseDictionaryMemory/PhraseDictionaryBinary/" -e "s#${transdir}/model/phrase-table\.gz#${bindir}/phrase-table#" -e "s#${transdir}/model/reordering-table\.wbe-msd-bidirectional-fe\.gz#${bindir}/reordering-table#" ${workdir}/mert-work/moses.ini \> ${bindir}/moses.ini

fi

# -- TESTING --
if [ ! $opt_overwrite ] && [ -f ${workdir}/score-dev.out ]; then
  echo [autoskip] testing
elif [ $opt_skip_test ]; then
  echo [skip] testing
else
#if [ $opt_test ]; then
  show_exec mkdir -p $workdir
  # -- TESTING PRAIN --
  show_exec rm -rf ${workdir}/filtered
  show_exec ${dir}/filter-moses.sh ${transdir}/model/moses.ini ${corpus}/test.true.${lang1} ${workdir}/filtered
  show_exec ${dir}/test-moses.sh ${task} ${workdir}/filtered/moses.ini ${corpus}/test.true.${lang1} ${corpus}/test.true.${lang2} plain --threads=${THREADS}
  show_exec rm -rf ${workdir}/filtered

  if [ -f ${bindir}/moses.ini ]; then
    # -- TESTING BINARISED --
    show_exec ${dir}/test-moses.sh ${task} ${bindir}/moses.ini ${corpus}/test.true.${lang1} ${corpus}/test.true.${lang2} tuned --threads=${THREADS}
    show_exec ${dir}/test-moses.sh ${task} ${bindir}/moses.ini ${corpus}/dev.true.${lang1} ${corpus}/dev.true.${lang2} dev --threads=${THREADS}
  fi
fi

head ${workdir}/score*

echo "##### End of script: $0 $*"

