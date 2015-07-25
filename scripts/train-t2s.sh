#!/bin/bash

dir="$(cd "$(dirname "${BASH_SOURCE:-${(%):-%N}}")"; pwd)"
source "${dir}/common.sh"

usage()
{
  echo "usage: $0 lang_id1 lang_id2 src1 src2"
  echo "usage: $0 lang_id1 lang_id2 --skip_format"
  echo ""
  echo "options:"
  echo "  --train_size={int}"
  echo "  --test_size={int}"
  echo "  --dev_size={int}"
  echo "  --dev_test_size={int}"
  echo "  --task_name={string}"
  echo "  --threads={int}"
  echo "  --skip_format"
  echo "  --skip_parse"
  echo "  --skip_lm"
  echo "  --skip_train"
  echo "  --skip_tuning"
  echo "  --skip_test"
  echo "  --overwrite"
}

if [ ${#ARGS[@]} -lt 4 ]
then
  usage
  exit 1
fi

lang1=${ARGS[0]}
lang2=${ARGS[1]}
src1=${ARGS[2]}
src2=${ARGS[3]}

if [ $opt_task_name ]; then
  task=$opt_task_name
else
  task="t2s_${lang1}-${lang2}"
fi

if [ -f "${task}/corpus/dev.true.${lang2}" ]; then
  if [ ${#ARGS[@]} -lt 2 ]; then
    usage
    exit 1
  fi
elif [ ${#ARGS[@]} -lt 4 ]; then
  usage
  exit 1
fi

if [ ${opt_threads} ]; then
  THREADS=${opt_threads}
fi

corpus="${task}/corpus"
langdir="${task}/LM_${lang2}"
transdir="${task}/TM"

# -- CORPUS PARSING --
options="--threads=${THREADS}"
if [ $opt_train_size ]
then
  options="$options --train_size=${opt_train_size}"
fi
if [ $opt_test_size ]
then
  options="$options --test_size=${opt_test_size}"
fi
if [ $opt_dev_size ]
then
  options="$options --dev_size=${opt_dev_size}"
fi
if [ $opt_dev_test_size ]; then
  options="$options --dev_test_size=${opt_dev_test_size}"
fi
options="$options --task_name=${task}"
#if [ ! ${opt_overwrite} ] && [ -f ${parsedir}/dev/true/${lang2} ]; then
#  echo [autoskip] corpus parsing
#elif [ $opt_skip_parse ]; then
#  echo [skip] corpus parsing
#else
#  show_exec "${dir}/parse-corpus.sh" ${lang1} ${src1} ${lang2} ${src2} ${options}
#fi
if [ ! ${opt_overwrite} ] && [ -f ${corpus}/dev.true.${lang2} ]; then
  echo [autoskip] corpus format
elif [ $opt_skip_format ]; then
  echo [skip] corpus format
else
  show_exec "${dir}/format-corpus.sh" ${lang1} ${src1} ${lang2} ${src2} ${options}
  show_exec "${dir}/parse-corpus.sh" ${corpus} ${options}
fi

# -- LANGUAGER MODELING --
if [ ! ${opt_overwrite} ] && [ -f ${langdir}/train.blm.${lang2} ]; then
  echo [autoskip] language modeling
elif [ $opt_skip_lm ]; then
  echo [skip] language modeling
else
  show_exec "${dir}/train-lm.sh" ${lang2} ${corpus}/train.true.${lang2} --task_name=${task}
  #show_exec "${dir}/train-lm.sh" ${lang2} ${parsedir}/train/true/${lang2} --task_name=${task}
fi

workdir="${task}/working"

if [ ! ${opt_overwrite} ] && [ -f ${transdir}/model/travatar.ini ]; then
  echo [autoskip] translation model
elif [ $opt_skip_train ]; then
  echo [skip] translation model
else
  src_file=${corpus}/train.true.${lang1}
  src_format=word
  if [ -f "${corpus}/train.tree.${lang1}" ]; then
    src_file=${corpus}/train.tree.${lang1}
    src_format=penn
  fi
  trg_file=${corpus}/train.true.${lang2}
  trg_format=word
  if [ -f "${corpus}/train.tree.${lang2}" ]; then
    trg_file=${corpus}/train.tree.${lang2}
    trg_format=penn
  fi
#  show_exec ${TRAVATAR}/script/train/train-travatar.pl -work_dir ${PWD}/${transdir} -src_file ${parsedir}/train/treelow/${lang1} -trg_file ${parsedir}/train/true/${lang2} -travatar_dir ${TRAVATAR} -bin_dir ${BIN} -lm_file ${PWD}/${langdir}/train.blm.${lang2} -threads ${THREADS}
#  show_exec ${TRAVATAR}/script/train/train-travatar.pl -work_dir ${PWD}/${transdir} -src_file ${parsedir}/train/treelow/${lang1} -trg_file ${parsedir}/train/treelow/${lang2} -travatar_dir ${TRAVATAR} -bin_dir ${BIN} -lm_file ${PWD}/${langdir}/train.blm.${lang2} -threads ${THREADS} -trg_format penn

  if [ "${src_format}" = "word" ]; then
    show_exec ${TRAVATAR}/script/train/train-travatar.pl -method hiero -work_dir ${PWD}/${transdir} -src_file ${src_file} -trg_file ${trg_file} -travatar_dir ${TRAVATAR} -bin_dir ${BIN} -lm_file ${PWD}/${langdir}/train.blm.${lang2} -threads ${THREADS} -src_format ${src_format} -trg_format ${trg_format}
  else
    show_exec ${TRAVATAR}/script/train/train-travatar.pl -work_dir ${PWD}/${transdir} -src_file ${src_file} -trg_file ${trg_file} -travatar_dir ${TRAVATAR} -bin_dir ${BIN} -lm_file ${PWD}/${langdir}/train.blm.${lang2} -threads ${THREADS} -src_format ${src_format} -trg_format ${trg_format}
  fi
fi

orig=$PWD

tunedir=${task}/tuned
src_dev=${orig}/${corpus}/dev.true.${lang1}
src_format=word
if [ -f "${orig}/${corpus}/dev.tree.${lang1}" ]; then
  src_dev=${orig}/${corpus}/dev.tree.${lang1}
  src_format=penn
fi

if [ ! ${opt_overwrite} ] && [ -f ${tunedir}/travatar.ini ]; then
  echo [autoskip] tuning
elif [ $opt_skip_tuning ]; then
  echo [skip] tuning
else
  orig=${PWD}
  show_exec ${dir}/tune-travatar.sh ${src_dev} ${orig}/${corpus}/dev.true.${lang2} ${orig}/${transdir}/model/travatar.ini ${task} --threads=${THREADS} --format=${src_format}
  show_exec mkdir -p ${tunedir}
  show_exec cp ${workdir}/mert-work/travatar.ini ${tunedir}
  show_exec rm -rf ${workdir}/mert-work/filtered
fi

src_test=${corpus}/dev.true.${lang1}
if [ -f "${corpus}/test.tree.${lang1}" ]; then
  src_test="${corpus}/test.tree.${lang1}"
fi

if [ -f ${workdir}/score-dev.out ]; then
  echo [autoskip] testing
elif [ $opt_skip_test ]; then
  echo [skip] testing
else
  show_exec ${dir}/test-travatar.sh ${task} ${transdir}/model/travatar.ini ${src_test} ${corpus}/test.true.${lang2} notune --threads=${THREADS} --format=${src_format}

  if [ -f ${tunedir}/travatar.ini ]; then
    show_exec ${dir}/test-travatar.sh ${task} ${tunedir}/travatar.ini ${src_test} ${corpus}/test.true.${lang2} tuned --threads=${THREADS} --format=${src_format}
    show_exec ${dir}/test-travatar.sh ${task} ${tunedir}/travatar.ini ${src_dev} ${corpus}/dev.true.${lang2} dev --threads=${THREADS} --format=${src_format}
  fi
fi

echo "End of script: $0"

