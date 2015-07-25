#!/bin/bash

NBEST=20
METHOD="count"
LEX_METHOD="interpolate"

dir="$(cd "$(dirname "${BASH_SOURCE:-${(%):-%N}}")"; pwd)"
source "${dir}/common.sh"

usage()
{
  echo "usage: $0 task1 task2 corpus_dir"
  echo ""
  echo "options:"
  echo "  --overwrite"
  echo "  --task_name={string}"
  echo "  --suffix={string}"
  echo "  --threads={integer}"
  echo "  --nbest={integer}"
  echo "  --method={count,interpolate}"
  echo "  --lexmethod={count,interpolate}"
  echo "  --noprefilter"
  echo "  --nulls={int}"
  echo "  --multitarget"
}

if [ ${#ARGS[@]} -lt 3 ]
then
  usage
  exit 1
fi

task1=${ARGS[0]}
task2=${ARGS[1]}
taskname1=$(basename $task1)
taskname2=$(basename $task2)
corpus_src=${ARGS[2]}

mt_method1=$(expr $taskname1 : '\(.*\)_..-..')
mt_method2=$(expr $taskname2 : '\(.*\)_..-..')
lang1_1=$(expr $taskname1 : '.*_\(..\)-..')
lang1_2=$(expr $taskname1 : '.*_..-\(..\)')
lang2_1=$(expr $taskname2 : '.*_\(..\)-..')
lang2_2=$(expr $taskname2 : '.*_..-\(..\)')

if [ "${lang1_2}" == "${lang2_1}" ]; then
  lang_src=${lang1_1}
  lang_pvt=${lang1_2}
  lang_trg=${lang2_2}
elif [ "${lang1_1}" == "${lang2_1}" ]; then
  lang_src=${lang1_2}
  lang_pvt=${lang1_1}
  lang_trg=${lang2_2}
else
  echo "can not solve pivot language"
  exit 1
fi

if [ "${mt_method1}" == "${mt_method2}" ]; then
  mt_method=${mt_method1}
else
  echo "can not solve pivot method"
  exit 1
fi

if [ "${mt_method}" == "pbmt" ]; then
  if [ "${opt_multitarget}" ]; then
    echo "multi-target is not supported for pbmt"
    exit 1
  fi
fi

if [ $opt_task_name ]; then
  task=$opt_task_name
else
  task="pivot_${mt_method}_${lang_src}-${lang_pvt}-${lang_trg}"
fi

if [ "$opt_suffix" ]; then
  task="${task}.${opt_suffix#.}"
fi

echo "MT METHOD: ${mt_method}"
echo "PIVOT METHOD: ${METHOD}"
echo "LANG SRC: ${lang_src}"
echo "LANG PVT: ${lang_pvt}"
echo "LANG TRG: ${lang_trg}"
echo "TASK: ${task}"

corpus="${task}/corpus"
#langdir=${task}/LM_${lang_trg}
langdir=${task}/LM
workdir="${task}/working"
transdir=${task}/TM
filterdir="${workdir}/filtered"

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

ask_continue ${task}
show_exec mkdir -p ${task}
show_exec mkdir -p ${workdir}
LOG=${task}/log
echo "[${stamp} ${HOST}] $0 $@" >> ${LOG}

test_options=""
if [ "${opt_multitarget}" ]; then
#  trg_test=${corpus}/test.${lang_trg}+${lang_pvt}
  trg_test=${corpus}/test.${lang_trg}
#  trg_dev=${corpus}/dev.${lang_trg}+${lang_pvt}
  trg_dev=${corpus}/dev.${lang_trg}
  test_options="--trg_factors=2"
else
  trg_test=${corpus}/test.${lang_trg}
  trg_dev=${corpus}/dev.${lang_trg}
fi

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

if [ "${opt_nbest}" ]; then
  NBEST="${opt_nbest}"
fi

#if [ $(expr ${opt_method} : '.*\(multi\)') ]; then
#  multitarget=true
#fi

#if [ -d ${corpus} ]; then
if [ -f ${trg_dev} ]; then
  echo [autoskip] link corpus
else
  # LINKING CORPUS DIR
#  show_exec ln -s $(abspath ${corpus_src}) ${corpus}
  show_exec mkdir -p ${corpus}

#  show_exec cp ${corpus_src}/devtest.{$lang_src,$lang_trg} ${corpus}
  show_exec ln ${corpus_src}/devtest.{$lang_src,$lang_trg} ${corpus}
#  show_exec cp ${corpus_src}/test.{$lang_src,$lang_trg} ${corpus}
  show_exec ln ${corpus_src}/test.{$lang_src,$lang_trg} ${corpus}
#  show_exec cp ${corpus_src}/dev.{$lang_src,$lang_trg} ${corpus}
  show_exec ln ${corpus_src}/dev.{$lang_src,$lang_trg} ${corpus}
#  if [ "${opt_multitarget}" ]; then
#    show_exec ln ${corpus_src}/test.${lang_pvt} ${corpus}
#    show_exec ln ${corpus_src}/dev.${lang_pvt} ${corpus}
#    show_exec paste ${task2}/corpus/test.{$lang_trg,$lang_pvt} \| sed -e '"s/\t/ |COL| /g"' \> ${trg_test}
#    show_exec paste ${corpus}/test.{$lang_trg,$lang_pvt} \| sed -e '"s/\t/ |COL| /g"' \> ${trg_test}
#    show_exec paste ${task2}/corpus/dev.{$lang_trg,$lang_pvt} \| sed -e '"s/\t/ |COL| /g"' \> ${trg_dev}
#    show_exec paste ${corpus}/dev.{$lang_trg,$lang_pvt} \| sed -e '"s/\t/ |COL| /g"' \> ${trg_dev}
#  fi
fi

if [ -d ${langdir} ]; then
  echo [autoskip] link LM
else
  # COPYING LM
#  show_exec cp -rf ${task2}/LM ${task}
  show_exec mkdir -p ${task}/LM
  show_exec ln ${task2}/LM/* ${task}/LM
fi

if [ -f ${plain_ini} ]; then
  echo [autoskip] pivot
else
  # COPYING CORPUS
#  show_exec mkdir -p ${corpus}
#  show_exec cp ${corpus_src}/devtest.true.{$lang_src,$lang_trg} ${corpus}
#  show_exec cp ${corpus_src}/test.true.{$lang_src,$lang_trg} ${corpus}
#  show_exec cp ${corpus_src}/dev.true.{$lang_src,$lang_trg} ${corpus}

  # COPYING LM
#  show_exec cp -rf ${task2}/LM_${lang_trg} ${task}
#  show_exec cp -rf ${task2}/LM ${task}
#  show_exec mkdir -p ${langdir}
#  show_exec cp ${task2}/LM_${lang_trg}/train.blm.${lang_trg} ${langdir}

  if [ "${mt_method}" == "pbmt" ]; then
    show_exec ${MOSES}/scripts/training/filter-model-given-input.pl ${workdir}/filtered ${task1}/TM/model/moses.ini ${src_devtest}
    show_exec mv ${workdir}/filtered/phrase-table*.gz ${workdir}/phrase_filtered.gz
    show_exec rm -rf ${workdir}/filtered
  elif [ "${mt_method}" == "t2s" ]; then
    # REVERSING
    show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/ruletable/reverse.py ${task1}/TM/model/rule-table.gz ${workdir}/rule_s2t
    show_exec cat ${workdir}/rule_s2t \| ${TRAVATAR}/script/train/filter-rule-table.py ${src_devtest} \> ${workdir}/rule_filtered.gz
  elif [ "${mt_method}" == "hiero" ]; then
    # FILTERING
#    show_exec zcat ${task1}/TM/model/rule-table.gz \| ${TRAVATAR}/script/train/filter-rule-table.py ${src_devtest} \> ${workdir}/rule_filtered
    show_exec zcat ${task1}/TM/model/rule-table.gz \| ${TRAVATAR}/script/train/filter-rule-table.py ${src_devtest} \| pv -WN filtered \> ${workdir}/rule_filtered
  fi

  if [ "${LEX_METHOD}" != "prodweight" ] && [ "${LEX_METHOD}" != "table" ]; then
#    lexfile="${transdir}/model/lex_${lang_src}-${lang_trg}"
    alignlex="${transdir}/model/align.lex"
    if [ -f "${alignlex}" ]; then
      echo [skip] calc lex probs
    else
      # 共起回数ピボットの場合、事前に語彙翻訳確率の算出が必要
      show_exec mkdir -p ${transdir}/model
      if [ "${decoder}" == "moses" ]; then
        show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/align2lex.py ${task1}/corpus/train.clean.{$lang_src,$lang_pvt} ${task1}/TM/model/aligned.grow-diag-final-and ${workdir}/lex_${lang_src}-${lang_pvt}
        show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/align2lex.py ${task2}/corpus/train.clean.{$lang_pvt,$lang_trg} ${task2}/TM/model/aligned.grow-diag-final-and ${workdir}/lex_${lang_pvt}-${lang_trg}
      elif [ "${decoder}" == "travatar" ]; then
        show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/align2lex.py ${task1}/corpus/train.clean.{$lang_src,$lang_pvt} ${task1}/TM/align/align.txt ${workdir}/lex_${lang_src}-${lang_pvt}
        show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/align2lex.py ${task2}/corpus/train.clean.{$lang_pvt,$lang_trg} ${task2}/TM/align/align.txt ${workdir}/lex_${lang_pvt}-${lang_trg}
      fi
      align_lex_method=$(echo $LEX_METHOD | sed -e 's/\(.*\)+table/\1/')
      show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/pivot_lex.py ${workdir}/lex_${lang_src}-${lang_pvt} ${workdir}/lex_${lang_pvt}-${lang_trg} ${alignlex} --method ${align_lex_method}
    fi
  fi

  # PIVOTING
  show_exec mkdir -p ${transdir}/model
  options="--workdir ${workdir}"
  options="${options} --nbest ${NBEST}"
  options="${options} --method ${METHOD}"
  options="${options} --lexmethod ${LEX_METHOD}"
  if [ "${opt_nulls}" ]; then
    options="${options} --nulls ${opt_nulls}"
  fi
  if [ "${LEX_METHOD}" != "prodweight" ]; then
    if [ "${LEX_METHOD}" != "table" ]; then
      options="${options} --alignlex ${alignlex}"
    fi
  fi
  if [ "${opt_noprefilter}" ]; then
    options="${options} --noprefilter=True"
  fi
  if [ "${opt_multitarget}" ]; then
    options="${options} --multitarget"
  fi
  if [ "${mt_method}" == "pbmt" ]; then
#    show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/triangulate.py ${task1}/TM/model/phrase-table.gz ${task2}/TM/model/phrase-table.gz ${transdir}/model/phrase-table.gz ${options}
    show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/triangulate.py ${workdir}/phrase_filtered.gz ${task2}/TM/model/phrase-table.gz ${transdir}/model/phrase-table.gz ${options}
    show_exec sed -e "s/${task2}/${task}/g" ${task2}/TM/model/moses.ini \> ${plain_ini}
    rm ${workdir}/phrase_filtered.gz
  elif [ "${mt_method}" == "hiero" ]; then
#    show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/ruletable/triangulate.py ${workdir}/rule_filtered.gz ${task2}/TM/model/rule-table.gz ${transdir}/model/rule-table.gz ${options}
    show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/ruletable/triangulate.py ${workdir}/rule_filtered ${task2}/TM/model/rule-table.gz ${transdir}/model/rule-table.gz ${options}
    show_exec cp ${task2}/TM/model/glue-rules ${transdir}/model/
    show_exec sed -e "s/${task2}/${task}/g" ${task2}/TM/model/travatar.ini \> ${plain_ini}
    rm ${workdir}/rule_filtered ${workdir}/rule_filtered.index
  elif [ "${mt_method}" == "t2s" ]; then
#    show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/ruletable/triangulate.py ${workdir}/rule_filtered.gz ${task2}/TM/model/rule-table.gz ${transdir}/model/rule-table.gz ${options}
    show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/ruletable/triangulate.py ${workdir}/rule_filtered ${task2}/TM/model/rule-table.gz ${transdir}/model/rule-table.gz ${options}
    show_exec sed -e "s/${task2}/${task}/g" ${task2}/TM/model/travatar.ini \> ${plain_ini}
  fi
  if [ -f ${workdir}/pivot/table.lex ]; then
    show_exec cp ${workdir}/pivot/table.lex ${transdir}/model/
  fi
  if [ -f ${workdir}/pivot/combined.lex ]; then
    show_exec cp ${workdir}/pivot/combined.lex ${transdir}/model/
  fi
#  if [ "${multitarget}" ]; then
  if [ "${opt_multitarget}" ]; then
#    show_exec cp -rf ${task1}/LM_${lang_pvt} ${task}
#    show_exec cp -rf ${task1}/LM ${task}
    show_exec ln ${task1}/LM/* ${task}/LM

    echo "x0:X @ S ||| x0:X @ S |COL| x0:X @ S ||| " > ${transdir}/model/glue-rules
    echo "x0:S x1:X @ S ||| x0:S x1:X @ S |COL| x0:S x1:X @ S ||| glue=1" >> ${transdir}/model/glue-rules

    lm_trg=$(ls $langdir | grep blm.$lang_trg)
    lm_pvt=$(ls $langdir | grep blm.$lang_pvt)
    echo "[tm_file]" > ${transdir}/model/travatar.ini
    echo $(abspath ${transdir}/model/rule-table.gz) >> ${transdir}/model/travatar.ini
    echo $(abspath ${transdir}/model/glue-rules) >> ${transdir}/model/travatar.ini
    echo "" >> ${transdir}/model/travatar.ini
    echo "[lm_file]" >> ${transdir}/model/travatar.ini
#    echo "$(abspath ${task}/LM/${lm_pvt})|factor=0,lm_feat=0lm,lm_unk_feat=0lmunk" >> ${transdir}/model/travatar.ini
#    echo "$(abspath ${task}/LM/${lm_trg})|factor=1,lm_feat=1lm,lm_unk_feat=1lmunk" >> ${transdir}/model/travatar.ini
    echo "$(abspath ${task}/LM/${lm_trg})|factor=0,lm_feat=0lm,lm_unk_feat=0lmunk" >> ${transdir}/model/travatar.ini
    echo "$(abspath ${task}/LM/${lm_pvt})|factor=1,lm_feat=1lm,lm_unk_feat=1lmunk" >> ${transdir}/model/travatar.ini
    echo "" >> ${transdir}/model/travatar.ini
    echo "[in_format]" >> ${transdir}/model/travatar.ini
    echo "word" >> ${transdir}/model/travatar.ini
    echo "" >> ${transdir}/model/travatar.ini
    echo "[tm_storage]" >> ${transdir}/model/travatar.ini
    echo "fsm" >> ${transdir}/model/travatar.ini
    echo "" >> ${transdir}/model/travatar.ini
    echo "[search]" >> ${transdir}/model/travatar.ini
    echo "cp" >> ${transdir}/model/travatar.ini
    echo "" >> ${transdir}/model/travatar.ini
    echo "[trg_factors]" >> ${transdir}/model/travatar.ini
    echo "2" >> ${transdir}/model/travatar.ini
    echo "" >> ${transdir}/model/travatar.ini
    echo "[hiero_span_limit]" >> ${transdir}/model/travatar.ini
    echo "20" >> ${transdir}/model/travatar.ini
    echo "1000" >> ${transdir}/model/travatar.ini
    echo "" >> ${transdir}/model/travatar.ini
    echo "[weight_vals]" >> ${transdir}/model/travatar.ini
    echo "0egfp=0.05" >> ${transdir}/model/travatar.ini
    echo "0egfl=0.05" >> ${transdir}/model/travatar.ini
    echo "0fgep=0.05" >> ${transdir}/model/travatar.ini
    echo "0fgel=0.05" >> ${transdir}/model/travatar.ini
    echo "0lm=0.3" >> ${transdir}/model/travatar.ini
    echo "0w=0.3" >> ${transdir}/model/travatar.ini
    echo "p=-0.15" >> ${transdir}/model/travatar.ini
    echo "unk=1" >> ${transdir}/model/travatar.ini
    echo "lfreq=0.05" >> ${transdir}/model/travatar.ini
  fi
  show_exec rm -rf ${workdir}/pivot
fi

# -- TESTING PLAIN --
if [ -f ${workdir}/score-plain.out ]; then
  echo [autoskip] testing plain
else
  show_exec ${dir}/filter.sh ${mt_method} ${plain_ini} ${src_test} ${workdir}/filtered
  show_exec ${dir}/test.sh ${mt_method} ${task} ${filtered_ini} ${src_test} ${trg_test} plain --threads=${THREADS} ${test_options}
fi

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
  #show_exec rm -rf ${workdir}/mert-work
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
      show_exec ${dir}/filter.sh ${mt_method} ${final_ini} ${src_test} ${workdir}/filtered
      show_exec ${dir}/test.sh ${mt_method} ${task} ${filtered_ini} ${src_test} ${trg_test} tuned --threads=${THREADS} ${test_options}
      show_exec ${dir}/filter.sh ${mt_method} ${final_ini} ${src_dev}  ${workdir}/filtered
      show_exec ${dir}/test.sh ${mt_method} ${task} ${filtered_ini} ${src_dev} ${trg_dev} dev --threads=${THREADS} ${test_options}
    fi
  fi
fi

#show_exec rm -rf ${workdir}/filtered
head ${workdir}/score* | tee -a ${LOG}

echo "##### End of script: $0 $*" | tee -a ${LOG}

