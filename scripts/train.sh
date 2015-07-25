#!/bin/bash

dir="$(cd "$(dirname "${BASH_SOURCE:-${(%):-%N}}")"; pwd)"
source "${dir}/common.sh"

echo "running script with PID: $$"

usage()
{
#  echo "usage: $0 mt_method lang_id1 lang_id2 src1 src2"
  echo "usage: $0 mt_method lang_id1 lang_id2 src1 src2 lm train_size dev_test_size"
  echo "usage: $0 mt_method lang_id1 lang_id2 lm --corpus=corpus_dir"
  echo "usage: $0 mt_method lang_id1 lang_id2 lm --resume"
  echo ""
  echo "mt_method: pbmt hiero t2s"
  echo ""
  echo "options:"
  echo "  --reordering"
  echo "  --corpus=corpus_dir"
  echo "  --suffix={string}"
  echo "  --task_name={string}"
  echo "  --threads={int}"
}

mt_method=${ARGS[0]}
lang1=${ARGS[1]}
lang2=${ARGS[2]}

if [ $opt_task_name ]; then
  task=$opt_task_name
else
  task="${mt_method}_${lang1}-${lang2}"
fi

if [ "${opt_suffix}" ]; then
  task=${task}.${opt_suffix#.}
fi

if [ "${opt_corpus}" ]; then
  if [ ${#ARGS[@]} -lt 4 ]; then
    usage
    exit 1
  fi
  lm=${ARGS[3]}
elif [ -f "${task}/corpus/dev.${lang2}" ]; then
  if [ ${#ARGS[@]} -lt 3 ]; then
    usage
    exit 1
  fi
  lm=${ARGS[3]}
#elif [ ${#ARGS[@]} -lt 5 ]; then
elif [ ${#ARGS[@]} -lt 8 ]; then
  usage
  exit 1
else
  src1=${ARGS[3]}
  src2=${ARGS[4]}
  lm=${ARGS[5]}
  opt_train_size=${ARGS[6]}
  opt_dev_test_size=${ARGS[7]}
fi

corpus="${task}/corpus"
langdir="${task}/LM"
transdir="${task}/TM"
workdir="${task}/working"
filterdir="${workdir}/filtered"

if [ "${mt_method}" == "moses" ]; then
  mt_method=pbmt
fi

case ${mt_method} in
  pbmt)
    decoder=moses
#    src_test=${corpus}/test.true.${lang1}
#    src_dev=${corpus}/dev.true.${lang1}
    src_test=${corpus}/test.${lang1}
    src_dev=${corpus}/dev.${lang1}
    ;;
  hiero)
    decoder=travatar
#    src_test=${corpus}/test.true.${lang1}
#    src_dev=${corpus}/dev.true.${lang1}
    src_test=${corpus}/test.${lang1}
    src_dev=${corpus}/dev.${lang1}
    ;;
  t2s)
    decoder=travatar
    src_test=${corpus}/test.tree.${lang1}
    src_dev=${corpus}/dev.tree.${lang1}
    ;;
  *)
    echo "mt_methos should be one of pbmt/hiero/t2s"
    exit 1
    ;;
esac
#trg_test=${corpus}/test.true.${lang2}
#trg_dev=${corpus}/dev.true.${lang2}
trg_test=${corpus}/test.${lang2}
trg_dev=${corpus}/dev.${lang2}

if [ "${mt_method}" == "t2s" ]; then
  case ${lang1} in
    en)
      ;;
    ja)
      ;;
    *)
      echo "lang1 should be one of en/ja"
      exit 1
  esac
fi

case ${decoder} in
  moses)
    bindir=${task}/binmodel
    plain_ini=${transdir}/model/moses.ini
    final_ini=${bindir}/moses.ini
    filtered_ini=${filterdir}/moses.ini
    ;;
  travatar)
    tunedir=${task}/tuned
    plain_ini=${transdir}/model/travatar.ini
    final_ini=${tunedir}/travatar.ini
    filtered_ini=${filterdir}/travatar.ini
    ;;
esac

ask_continue ${task}
show_exec mkdir -p ${task}
show_exec mkdir -p ${workdir}
LOG=${task}/log
echo "[${stamp} ${HOST}] $0 $*" >> ${LOG}

# -- CORPUS FORMATTING --
#if [ -f ${trg_dev} ]; then
if [ -f ${corpus}/train.clean.${lang2} ]; then
  echo [autoskip] corpus format
else
  mkdir -p ${corpus}
  if [ ! -f ${trg_dev} ]; then
    if [ "${opt_corpus}" ]; then
      show_exec ln ${opt_corpus}/train.{$lang1,$lang2} ${corpus}
      show_exec ln ${opt_corpus}/devtest.{$lang1,$lang2} ${corpus}
      show_exec ln ${opt_corpus}/test.{$lang1,$lang2} ${corpus}
      show_exec ln ${opt_corpus}/dev.{$lang1,$lang2} ${corpus}
    else
      options=""
      options="$options --train_size=${opt_train_size}"
      options="$options --dev_test_size=${opt_dev_test_size}"
      options="$options --task_name=${task}"
      show_exec "${dir}/format-corpus.sh" ${lang1} ${src1} ${lang2} ${src2} ${options} --threads=${THREADS}
    fi
  fi
  show_exec ${TRAVATAR}/script/train/clean-corpus.pl -max_len ${CLEAN_LENGTH} ${corpus}/train.{$lang1,$lang2} ${corpus}/train.clean.{$lang1,$lang2}
  if [ "${mt_method}" == "t2s" ]; then
    show_exec "${dir}/parse-corpus.sh" ${corpus} ${options} --threads=${THREADS}
  fi
fi

lm_file="blm.${lang2}"
# -- LINKING LANGUAGE MODEL --
if [ ! -d ${langdir} ]; then
  show_exec mkdir -p ${langdir}
#  show_exec ln -s $(abspath ${lm}) ${langdir}/
  show_exec ln ${lm} ${langdir}/${lm_file}
fi
lm=$(abspath $langdir/$lm_file)

# -- TRAINING --
if [ -f "${plain_ini}" ]; then
  echo [autoskip] translation model
else
  if [ ${mt_method} == "pbmt" ]; then
    if [ "${opt_reordering}" ]; then
      show_exec $MOSES/scripts/training/train-model.perl -root-dir $transdir -corpus $corpus/train.clean -f ${lang1} -e ${lang2} -alignment grow-diag-final-and -reordering msd-bidirectional-fe -lm 0:${ORDER}:${lm}:8 -external-bin-dir $GIZA -cores ${THREADS} \> ${task}/training.out
    else
      #show_exec $MOSES/scripts/training/train-model.perl -root-dir $transdir -corpus $corpus/train.clean -f ${lang1} -e ${lang2} -alignment grow-diag-final-and -reordering distance -lm 0:${ORDER}:$(pwd)/$langdir/train.blm.${lang2}:8 -external-bin-dir $GIZA -cores ${THREADS} \> ${task}/training.out
      show_exec $MOSES/scripts/training/train-model.perl -root-dir $transdir -corpus $corpus/train.clean -f ${lang1} -e ${lang2} -alignment grow-diag-final-and -reordering distance -lm 0:${ORDER}:${lm}:8 -external-bin-dir $GIZA -cores ${THREADS} \> ${task}/training.out
    fi
  elif [ ${mt_method} == "hiero" ]; then
#    show_exec ${TRAVATAR}/script/train/train-travatar.pl -method hiero -work_dir ${PWD}/${transdir} -src_file ${corpus}/train.clean.${lang1} -trg_file ${corpus}/train.clean.${lang2} -travatar_dir ${TRAVATAR} -bin_dir ${BIN} -lm_file ${PWD}/${langdir}/train.blm.${lang2} -threads ${THREADS}
#    show_exec ${TRAVATAR}/script/train/train-travatar.pl -method hiero -work_dir ${PWD}/${transdir} -src_file ${corpus}/train.clean.${lang1} -trg_file ${corpus}/train.clean.${lang2} -travatar_dir ${TRAVATAR} -bin_dir ${BIN} -lm_file ${lm} -threads ${THREADS}
    show_exec ${TRAVATAR}/script/train/train-travatar.pl -method hiero -work_dir ${PWD}/${transdir} -src_file ${corpus}/train.clean.${lang1} -trg_file ${corpus}/train.clean.${lang2} -travatar_dir ${TRAVATAR} -bin_dir ${GIZA} -lm_file ${lm} -threads ${THREADS} -progress
    show_exec mv ${transdir}/model/rule-table.gz ${transdir}/model/rule-table.full.gz
    show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/ruletable/filter.py ${transdir}/model/rule-table.full.gz ${transdir}/model/rule-table.gz "'c.c >= 1'"
  elif [ ${mt_method} == "t2s" ]; then
    src_file=${corpus}/train.tree.${lang1}
    if [ -f "${corpus}/train.tree.${lang2}" ]; then
      trg_file=${corpus}/train.tree.${lang2}
      trg_format=penn
    else
      trg_file=${corpus}/train.clean.${lang2}
      trg_format=word
    fi
#    show_exec ${TRAVATAR}/script/train/train-travatar.pl -work_dir ${PWD}/${transdir} -src_file ${src_file} -trg_file ${trg_file} -travatar_dir ${TRAVATAR} -bin_dir ${BIN} -lm_file ${lm} -threads ${THREADS} -src_format penn -trg_format ${trg_format}
    show_exec ${TRAVATAR}/script/train/train-travatar.pl -work_dir ${PWD}/${transdir} -src_file ${src_file} -trg_file ${trg_file} -travatar_dir ${TRAVATAR} -bin_dir ${GIZA} -lm_file ${lm} -threads ${THREADS} -src_format penn -trg_format ${trg_format}
  fi
fi

# -- TESTING PLAIN --
if [ -f ${workdir}/score-plain.out ]; then
  echo [autoskip] testing plain
else
  show_exec ${dir}/filter.sh ${mt_method} ${plain_ini} ${src_test} ${workdir}/filtered
  show_exec ${dir}/test.sh ${mt_method} ${task} ${filtered_ini} ${src_test} ${trg_test} plain --threads=${THREADS}
fi

# -- TUNING --
if [ -f "${final_ini}" ]; then
  echo [autoskip] tuning
else
#  show_exec ${dir}/tune.sh ${mt_method} ${corpus}/dev.true.${lang1} ${corpus}/dev.true.${lang2} ${plain_ini} ${task} --threads=${THREADS}
  show_exec ${dir}/tune.sh ${mt_method} ${src_dev} ${trg_dev} ${plain_ini} ${task} --threads=${THREADS}

  if [ "${mt_method}" == "pbmt" ]; then
    # -- BINARIZING --
    show_exec mkdir -p ${bindir}
    if [ "${opt_reordering}" ]; then
      show_exec ${BIN}/processLexicalTable -in ${transdir}/model/reordering-table.wbe-msd-bidirectional-fe.gz -out ${bindir}/reordering-table
    fi
    show_exec ${BIN}/processPhraseTable -ttable 0 0 ${transdir}/model/phrase-table.gz -nscores 5 -out ${bindir}/phrase-table
    show_exec sed -e "s/PhraseDictionaryMemory/PhraseDictionaryBinary/" -e "s#${transdir}/model/phrase-table\.gz#${bindir}/phrase-table#" -e "s#${transdir}/model/reordering-table\.wbe-msd-bidirectional-fe\.gz#${bindir}/reordering-table#" ${workdir}/mert-work/moses.ini \> ${final_ini}
  else
    # -- MAKING TUNED DIR --
    show_exec mkdir -p ${tunedir}
    show_exec cp ${workdir}/mert-work/travatar.ini ${tunedir}
  fi
#  show_exec rm -rf ${workdir}/mert-work
  show_exec rm -rf ${workdir}/mert-work/filtered
fi

# -- TESTING --
if [ -f ${workdir}/score-dev.out ]; then
  echo [autoskip] testing
else
  if [ -f "${final_ini}" ]; then
    # -- TESTING TUNED AND DEV --
    if [ "${mt_method}" == "pbmt" ]; then
      show_exec ${dir}/test.sh ${mt_method} ${task} ${final_ini} ${src_test} ${trg_test} tuned --threads=${THREADS}
      show_exec ${dir}/test.sh ${mt_method} ${task} ${final_ini} ${src_dev}  ${trg_dev}  dev --threads=${THREADS}
    else
#      show_exec ${dir}/filter.sh ${mt_method} ${final_ini} ${corpus}/test.true.${lang1} ${workdir}/filtered
      show_exec ${dir}/filter.sh ${mt_method} ${final_ini} ${src_test} ${workdir}/filtered
#      show_exec ${dir}/test.sh ${mt_method} ${task} ${filtered_ini} ${corpus}/test.true.{$lang1,$lang2} tuned --threads=${THREADS}
      show_exec ${dir}/test.sh ${mt_method} ${task} ${filtered_ini} ${src_test} ${trg_test} tuned --threads=${THREADS}
#      show_exec ${dir}/filter.sh ${mt_method} ${final_ini} ${corpus}/dev.true.${lang1} ${workdir}/filtered
      show_exec ${dir}/filter.sh ${mt_method} ${final_ini} ${src_dev} ${workdir}/filtered
#      show_exec ${dir}/test.sh ${mt_method} ${task} ${filtered_ini} ${corpus}/dev.true.{$lang1,$lang2} dev --threads=${THREADS}
      show_exec ${dir}/test.sh ${mt_method} ${task} ${filtered_ini} ${src_dev} ${trg_dev} dev --threads=${THREADS}
    fi
  fi
fi

show_exec rm -rf ${workdir}/filtered

head ${workdir}/score* | tee -a ${LOG}

echo "##### End of script: $0 $*" | tee -a ${LOG}

