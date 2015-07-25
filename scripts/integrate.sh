#!/bin/bash

NBEST=20
METHOD="count"
LEX_METHOD="interpolate"

dir="$(cd "$(dirname "${BASH_SOURCE:-${(%):-%N}}")"; pwd)"
source "${dir}/common.sh"

echo "running script with PID: $$"

usage()
{
#  echo "usage: $0 lang1 lang2 task1 task2 corpus_dir"
  echo "usage: $0 task1 task2 corpus_dir lm_trg"
  echo ""
  echo "options:"
  echo "  --overwrite"
  echo "  --task_name={string}"
  echo "  --suffix{string}"
  echo "  --threads={integer}"
  echo "  --nbest={integer}"
  echo "  --method={string}"
  echo "  --lexmethod={lexmethod}"
  echo "  --lm_trg={filepath}"
}

#if [ ${#ARGS[@]} -lt 5 ]
if [ ${#ARGS[@]} -lt 4 ]
then
  usage
  exit 1
fi

task1=${ARGS[0]}
task2=${ARGS[1]}
corpus_src=${ARGS[2]}
lm_trg=${ARGS[3]}

taskname1=$(basename $task1)
taskname2=$(basename $task2)

mt_method1=$(get_mt_method $taskname1)
lang_task1_src=$(get_lang_src $taskname1)
lang_task1_trg=$(get_lang_trg $taskname1)
mt_method2=$(get_mt_method $taskname2)
lang_task2_src=$(get_lang_src $taskname2)
lang_task2_trg=$(get_lang_trg $taskname2)

if [ "${mt_method1}" == "${mt_method2}" ]; then
  mt_method=${mt_method1}
else
  echo "mt_method: ${mt_method1} != ${mt_method2}"
  exit 1
fi

if [ "${lang_task1_src}" == "${lang_task2_src}" ]; then
  lang_src=${lang_task1_src}
else
  echo "src: ${lang_task1_src} != ${lang_task2_src}"
  exit 1
fi

if [ "${lang_task1_trg}" == "${lang_task2_trg}" ]; then
  lang_trg=${lang_task1_trg}
else
  echo "trg: ${lang_task1_trg} != ${lang_task2_trg}"
  exit 1
fi

if [ $opt_task_name ]; then
  task=$opt_task_name
else
  task="integrate_${mt_method}_${lang_src}-${lang_trg}"
fi

if [ "$opt_suffix" ]; then
  task="${task}.${opt_suffix}"
fi

ask_continue ${task}
show_exec mkdir -p ${task}
LOG=${task}/log
echo "[${stamp} ${HOST}] $0 $*" >> ${LOG}

corpus="${task}/corpus"
langdir=${task}/LM_${lang_trg}
workdir="${task}/working"
transdir=${task}/TM
filterdir="${workdir}/filtered"
show_exec mkdir -p ${workdir}

case ${mt_method} in
  pbmt)
    decoder=moses
    src_test=${corpus}/test.${lang_src}
    src_dev=${corpus}/dev.${lang_src}
    src_devtest=${corpus}/devtest.${lang_src}
    ;;
  hiero)
    decoder=travatar
    src_test=${corpus}/test.${lang_src}
    src_dev=${corpus}/dev.${lang_src}
    src_devtest=${corpus}/devtest.${lang_src}
    ;;
  t2s)
    decoder=travatar
    src_test=${corpus}/test.tree.${lang_src}
    src_dev=${corpus}/dev.tree.${lang_src}
    src_devtest=${corpus}/devtest.tree.${lang_src}
    ;;
  *)
    echo "mt_methos should be one of pbmt/hiero/t2s"
    exit 1
    ;;
esac
trg_test=${corpus}/test.${lang_trg}
trg_dev=${corpus}/dev.${lang_trg}


case ${decoder} in
  moses)
    bindir=${task}/binmodel
    plain_ini=${transdir}/model/moses.ini
    final_ini=${bindir}/moses.ini
    filtered_ini=${filterdir}/moses.ini
    ${dir}/wait-file.sh ${task1}/TM/model/moses.ini
    ${dir}/wait-file.sh ${task2}/TM/model/moses.ini
    ;;
  travatar)
    tunedir=${task}/tuned
    plain_ini=${transdir}/model/travatar.ini
    final_ini=${tunedir}/travatar.ini
    filtered_ini=${filterdir}/travatar.ini
    ${dir}/wait-file.sh ${task1}/TM/model/travatar.ini
    ${dir}/wait-file.sh ${task2}/TM/model/travatar.ini
    ;;
esac


if [ -f ${transdir}/model/moses.ini ]; then
  echo [autoskip] integrate
else
  show_exec mkdir -p ${transdir}/model
  ${dir}/wait-file.sh ${task1}/TM/model/moses.ini
  ${dir}/wait-file.sh ${task2}/TM/model/moses.ini

  # COPYING CORPUS
  show_exec mkdir -p ${corpus}
#  show_exec cp ${corpus_src}/devtest.true.{$lang_src,$lang_trg} ${corpus}
  show_exec cp ${corpus_src}/devtest.{$lang_src,$lang_trg} ${corpus}
#  show_exec cp ${corpus_src}/test.true.{$lang_src,$lang_trg} ${corpus}
  show_exec cp ${corpus_src}/test.{$lang_src,$lang_trg} ${corpus}
#  show_exec cp ${corpus_src}/dev.true.{$lang_src,$lang_trg} ${corpus}
  show_exec cp ${corpus_src}/dev.{$lang_src,$lang_trg} ${corpus}

  # FILTERING
  if [ "${mt_method}" == "pbmt" ]; then
#    show_exec ${MOSES}/scripts/training/filter-model-given-input.pl ${workdir}/filtered ${task1}/TM/model/moses.ini ${corpus}/devtest.true.${lang_src}
    show_exec ${MOSES}/scripts/training/filter-model-given-input.pl ${workdir}/filtered ${task1}/TM/model/moses.ini ${corpus}/devtest.${lang_src}
    show_exec mv ${workdir}/filtered/phrase-table*.gz ${workdir}/phrase_filtered1.gz
    show_exec rm -rf ${workdir}/filtered
#    show_exec ${MOSES}/scripts/training/filter-model-given-input.pl ${workdir}/filtered ${task2}/TM/model/moses.ini ${corpus}/devtest.true.${lang_src}
    show_exec ${MOSES}/scripts/training/filter-model-given-input.pl ${workdir}/filtered ${task2}/TM/model/moses.ini ${corpus}/devtest.${lang_src}
    show_exec mv ${workdir}/filtered/phrase-table*.gz ${workdir}/phrase_filtered2.gz
    show_exec rm -rf ${workdir}/filtered
  elif [ "${mt_method}" == "t2s" ]; then
    # REVERSING
    show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/ruletable/reverse.py ${task1}/TM/model/rule-table.gz ${workdir}/rule_s2t
#    show_exec cat ${workdir}/rule_s2t \| ${TRAVATAR}/script/train/filter-rule-table.py ${corpus}/devtest.true.${lang_src} \| gzip \> ${workdir}/rule_filtered.gz
#    show_exec cat ${workdir}/rule_s2t \| ${TRAVATAR}/script/train/filter-rule-table.py ${corpus}/devtest.true.${lang_src} \> ${workdir}/rule_filtered.gz
    show_exec cat ${workdir}/rule_s2t \| ${TRAVATAR}/script/train/filter-rule-table.py ${corpus}/devtest.${lang_src} \> ${workdir}/rule_filtered.gz
  elif [ "${mt_method}" == "hiero" ]; then
    # FILTERING
#    show_exec zcat ${task1}/TM/model/rule-table.gz \| ${TRAVATAR}/script/train/filter-rule-table.py ${corpus}/devtest.true.${lang_src} \> ${workdir}/rule_filtered.gz
#    show_exec zcat ${task1}/TM/model/rule-table.gz \| ${TRAVATAR}/script/train/filter-rule-table.py ${corpus}/devtest.true.${lang_src} \> ${workdir}/rule_filtered
    show_exec zcat ${task1}/TM/model/rule-table.gz \| ${TRAVATAR}/script/train/filter-rule-table.py ${corpus}/devtest.${lang_src} \> ${workdir}/rule_filtered
  fi

  if [ "${LEX_METHOD}" != "interpolate" ]; then
#    lexfile="${transdir}/model/lex_${lang_src}-${lang_trg}"
    lexfile="${transdir}/model/combined.lex"
    if [ -f "${lexfile}" ]; then
      echo [skip] calc lex probs
    else
      # 共起回数ピボットの場合、事前に語彙翻訳確率の算出が必要
      lexfile1="${task1}/TM/model/lex_${lang_src}-${lang_trg}"
      lexfile2="${task2}/TM/model/lex_${lang_src}-${lang_trg}"
      if [ -f "${lexfile1}" ]; then
        cp ${lexfile1} ${workdir}/lex1
      else
        show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/align2lex.py ${task1}/corpus/train.clean.{$lang_src,$lang_trg} ${task1}/TM/model/aligned.grow-diag-final-and ${workdir}/lex1
      fi
      if [ -f "${lexfile2}" ]; then
        cp ${lexfile2} ${workdir}/lex2
      else
        if [ -f ${task2}/TM/model/align.lex ]; then
          show_exec cp ${task2}/TM/model/align.lex ${workdir}/lex2
        else
          show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/align2lex.py ${task2}/corpus/train.clean.{$lang_src,$lang_trg} ${task2}/TM/model/aligned.grow-diag-final-and ${workdir}/lex2
        fi
      fi
  #    show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/pivot_lex.py ${workdir}/lex1 ${workdir}/lex2 ${lexfile}
      show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/combine_lex.py ${workdir}/lex1 ${workdir}/lex2 ${lexfile}
    fi
  fi
  # INTEGRATING
  options="--workdir ${workdir}"
  options="${options} --method ${METHOD}"
  options="${options} --lexmethod ${LEX_METHOD}"
  if [ "${THRESHOLD}" ]; then
    options="${options} --threshold ${THRESHOLD}"
  fi
  if [ "${opt_nbest}" ]; then
    options="${options} --nbest ${opt_nbest}"
  else
    options="${options} --nbest ${NBEST}"
  fi
  if [ -f "${lexfile}" ]; then
    options="${options} --lexfile ${lexfile}"
  fi
  if [ "${mt_method}" == "pbmt" ]; then
  #  show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/integrate.py ${task1}/TM/model/phrase-table.gz ${task2}/TM/model/phrase-table.gz ${lexfile} ${transdir}/model/phrase-table.gz ${options}
  #  show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/integrate.py ${task1}/TM/model/phrase-table.gz ${task2}/TM/model/phrase-table.gz ${transdir}/model/phrase-table.gz ${options}
    show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/integrate.py ${workdir}/phrase_filtered1.gz ${workdir}/phrase_filtered2.gz ${transdir}/model/phrase-table.gz ${options}
#    lm_param="KENLM lazyken=0 name=LM0 factor=0 path=${lm_trg} order=5"
    lm_param="KENLM lazyken=0 name=LM0 factor=0 path=$(abspath ${lm_trg}) order=5"
#    show_exec sed -e "s/${task1}/${task}/g" -e "s/KENLM.*$/${lm_param}/g" ${task1}/TM/model/moses.ini \> ${transdir}/model/moses.ini
    show_exec sed -e "'s#$(abspath ${task1})#$(abspath ${task})#g'" -e "'s#KENLM.*#${lm_param}#'" ${task1}/TM/model/moses.ini \> ${transdir}/model/moses.ini
    show_exec rm -rf ${workdir}/phrase_filtered*.gz
    show_exec rm -rf ${workdir}/lex*
  elif [ "${mt_method}" == "hiero" ]; then
    show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/integrate.py ${workdir}/phrase_filtered1.gz ${workdir}/phrase_filtered2.gz ${transdir}/model/phrase-table.gz ${options}
  fi
  show_exec rm -rf ${workdir}/integrate
fi

# -- TESTING PLAIN --
if [ -f ${workdir}/score-plain.out ]; then
  echo [autoskip] testing plain
else
  show_exec ${dir}/filter.sh ${mt_method} ${plain_ini} ${src_test} ${workdir}/filtered
  show_exec ${dir}/test.sh ${mt_method} ${task} ${filtered_ini} ${src_test} ${trg_test} plain --threads=${THREADS} ${test_options}
fi

#bindir=${task}/binmodel
## -- TUNING --
#if [ ! $opt_overwrite ] && [ -f ${bindir}/moses.ini ]; then
#  echo [autoskip] tuning
#elif [ $opt_skip_tuning ]; then
#  echo [skip] tuning
#else
##if [ $opt_tuning ]; then
##  show_exec ${dir}/tune-moses.sh ${corpus}/dev.true.${lang_src} ${corpus}/dev.true.${lang_trg} ${transdir}/model/moses.ini ${task} --threads=${THREADS}
#  show_exec ${dir}/tune-moses.sh ${corpus}/dev.${lang_src} ${corpus}/dev.${lang_trg} ${transdir}/model/moses.ini ${task} --threads=${THREADS}
#
#  # -- BINARIZING --
#  show_exec mkdir -p ${bindir}
#  show_exec ${BIN}/processPhraseTable -ttable 0 0 ${transdir}/model/phrase-table.gz -nscores 5 -out ${bindir}/phrase-table
#  show_exec sed -e "s/PhraseDictionaryMemory/PhraseDictionaryBinary/" -e "s#${transdir}/model/phrase-table\.gz#${bindir}/phrase-table#" -e "s#${transdir}/model/reordering-table\.wbe-msd-bidirectional-fe\.gz#${bindir}/reordering-table#" ${workdir}/mert-work/moses.ini \> ${bindir}/moses.ini
#
#fi

# -- TUNING --
if [ -f "${final_ini}" ]; then
  echo [autoskip] tuning
elif [ $opt_skip_tuning ]; then
  echo [skip] tuning
else
  show_exec ${dir}/tune.sh ${mt_method} ${src_dev} ${trg_dev} ${plain_ini} ${task} --threads=${THREADS}

  if [ "${decoder}" == "moses" ]; then
    # -- BINARIZING --
    show_exec mkdir -p ${bindir}
    show_exec ${BIN}/processPhraseTable -ttable 0 0 ${transdir}/model/phrase-table.gz -nscores 5 -out ${bindir}/phrase-table
    show_exec sed -e "s/PhraseDictionaryMemory/PhraseDictionaryBinary/" -e "s#${transdir}/model/phrase-table\.gz#${bindir}/phrase-table#" -e "s#${transdir}/model/reordering-table\.wbe-msd-bidirectional-fe\.gz#${bindir}/reordering-table#" ${workdir}/mert-work/moses.ini \> ${final_ini}
  elif [ "${decoder}" == "travatar" ]; then
    # -- MAKING TUNED DIR --
    show_exec mkdir -p ${tunedir}
    show_exec cp ${workdir}/mert-work/travatar.ini ${tunedir}
  fi
  show_exec rm -rf ${workdir}/mert-work
fi


## -- TESTING --
#if [ ! $opt_overwrite ] && [ -f ${workdir}/score-dev.out ]; then
#  echo [autoskip] testing
#elif [ $opt_skip_test ]; then
#  echo [skip] testing
#else
##if [ $opt_test ]; then
#  show_exec mkdir -p $workdir
#  # -- TESTING PRAIN --
#  show_exec rm -rf ${workdir}/filtered
##  show_exec ${dir}/filter-moses.sh ${transdir}/model/moses.ini ${corpus}/test.true.${lang_src} ${workdir}/filtered
#  show_exec ${dir}/filter-moses.sh ${transdir}/model/moses.ini ${corpus}/test.${lang_src} ${workdir}/filtered
##  show_exec ${dir}/test-moses.sh ${task} ${workdir}/filtered/moses.ini ${corpus}/test.true.${lang_src} ${corpus}/test.true.${lang_trg} plain --threads=${THREADS}
#  show_exec ${dir}/test-moses.sh ${task} ${workdir}/filtered/moses.ini ${corpus}/test.${lang_src} ${corpus}/test.${lang_trg} plain --threads=${THREADS}
#  show_exec rm -rf ${workdir}/filtered
#
#  if [ -f ${bindir}/moses.ini ]; then
#    # -- TESTING BINARISED --
##    show_exec ${dir}/test-moses.sh ${task} ${bindir}/moses.ini ${corpus}/test.true.${lang_src} ${corpus}/test.true.${lang_trg} tuned --threads=${THREADS}
#    show_exec ${dir}/test-moses.sh ${task} ${bindir}/moses.ini ${corpus}/test.${lang_src} ${corpus}/test.${lang_trg} tuned --threads=${THREADS}
##    show_exec ${dir}/test-moses.sh ${task} ${bindir}/moses.ini ${corpus}/dev.true.${lang_src} ${corpus}/dev.true.${lang_trg} dev --threads=${THREADS}
#    show_exec ${dir}/test-moses.sh ${task} ${bindir}/moses.ini ${corpus}/dev.${lang_src} ${corpus}/dev.${lang_trg} dev --threads=${THREADS}
#  fi
#fi

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
      show_exec ${dir}/filter.sh ${mt_method} ${final_ini} ${src_test} ${workdir}/filtered
      show_exec ${dir}/test.sh ${mt_method} ${task} ${filtered_ini} ${src_test} ${trg_test} tuned --threads=${THREADS} ${test_options}
      show_exec ${dir}/filter.sh ${mt_method} ${final_ini} ${src_dev}  ${workdir}/filtered
      show_exec ${dir}/test.sh ${mt_method} ${task} ${filtered_ini} ${src_dev} ${trg_dev} dev --threads=${THREADS} ${test_options}
    fi
  fi
fi

head ${workdir}/score* | tee -a ${LOG}

echo "##### End of script: $0 $*" | tee -a ${LOG}

