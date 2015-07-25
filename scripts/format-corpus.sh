#!/bin/bash

#CLEAN_LENGTH=80
CLEAN_LENGTH=60

# -- PARTIAL CORPUS --
#TRAIN_SIZE=100000
#TEST_SIZE=1500
#DEV_SIZE=1500
TRAIN_SIZE=0
TEST_SIZE=0
DEV_SIZE=0

dir="$(cd "$(dirname "${BASH_SOURCE:-${(%):-%N}}")"; pwd)"
source "${dir}/common.sh"

usage()
{
  echo "usage: $0 lang_id1 src1 [[lang_id2 src2] ...]"
  echo ""
  echo "options:"
  echo "  --train_size={int}"
  echo "  --test_size={int}"
  echo "  --dev_size={int}"
  echo "  --dev_test_size={int}"
  echo "  --task_name={string}"
}

tokenize()
{
  lang=$1
  prefix=$2
  src=${corpus}/${prefix}.${lang}
  output=${corpus}/${prefix}.tok.${lang}

  if [ $lang = "zh" ]; then
#    show_exec $KYTEA -notags -model $KYTEA_ZH_DIC \< ${src} \> ${output}
    show_exec $KYTEA -notags -model $KYTEA_ZH_DIC -wsconst D \< ${src} \> ${output}
  elif [ $lang = "ja" ]; then
#    show_exec $KYTEA -notags \< ${src} \> ${output}
    show_exec $KYTEA -notags -wsconst D \< ${src} \> ${output}
  else
    show_exec ~/exp/moses/scripts/tokenizer/tokenizer.perl -l $lang \< $src \> ${output}
  fi
}

train_truecaser()
{
  lang=$1
  prefix=$2
  src=${corpus}/${prefix}.tok.${lang}
  model=${corpus}/truecase-model.${lang}
  show_exec $MOSES/scripts/recaser/train-truecaser.perl --model ${model} --corpus ${src}
}

truecase()
{
  lang=$1
  prefix=$2
  if [ $lang = "zh" ]; then
    show_exec mv ${corpus}/${prefix}.tok.${lang} ${corpus}/${prefix}.true.${lang}
  elif [ $lang = "ja" ]; then
    show_exec mv ${corpus}/${prefix}.tok.${lang} ${corpus}/${prefix}.true.${lang}
  else
    show_exec $MOSES/scripts/recaser/truecase.perl --model ${corpus}/truecase-model.${lang} \< ${corpus}/${prefix}.tok.${lang} \> ${corpus}/${prefix}.true.${lang}
  fi
}

if [ ${#ARGS[@]} -lt 2 ]
then
  usage
  exit 1
fi

if [[ $(perl -e "print ${#ARGS[@]} % 2") == 1 ]]; then
  usage
  echo "num args should be even: ${#ARGS[@]}"
  exit 1
fi

langs=()
files=()
for (( i = 0; i < ${#ARGS[@]}; i +=2 )); do
  langs+=(${ARGS[$i]})
  files+=(${ARGS[$i+1]})
done
echo LANGS: ${langs[@]}
echo FILES: ${files[@]}

declare -i train_size=$opt_train_size
if [ $train_size -lt 1 ]
then
  train_size=$TRAIN_SIZE
fi

declare -i test_size=$opt_test_size
if [ $test_size -lt 1 ]
then
  test_size=$TEST_SIZE
fi

declare -i dev_size=$opt_dev_size
if [ $dev_size -lt 1 ]
then
  dev_size=$DEV_SIZE
fi

echo TRAIN_SIZE: $train_size
if [ ${opt_dev_test_size} ]; then
  echo TEST_SIZE : $opt_dev_test_size
  echo DEV_SIZE  : $opt_dev_test_size
else
  echo TEST_SIZE : $test_size
  echo DEV_SIZE  : $dev_size
fi

if [ $opt_task_name ]; then
  corpus="${opt_task_name}/corpus"
else
  tuple=$(echo ${langs[@]} | sed -e 's/ /-/g')
  corpus="corpus_${tuple}"
fi
show_exec mkdir -p $corpus

if [[ ${train_size} -gt 0 ]]; then
  let offset=1
  if [ "${opt_dev_test_size}" ]; then
    let offset=${offset}+${opt_dev_test_size}*2
  fi
  if [ "${opt_test_size}" ]; then
    let offset=${offset}+${opt_test_size}
  fi
  if [ "${opt_dev_size}" ]; then
    let offset=${offset}+${opt_dev_size}
  fi
  for (( i = 0; i < ${#langs[@]}; i++ )); do
#    show_exec head -n ${train_size} ${files[$i]} \> ${corpus}/train.${langs[$i]}
    show_exec tail -n +${offset} ${files[$i]} \|  head -n ${train_size} \> ${corpus}/train.${langs[$i]}
  done
fi

#tokenize ${lang1} train
#tokenize ${lang2} train
#train_truecaser ${lang1} train
#train_truecaser ${lang2} train
#truecase ${lang1} train
#truecase ${lang2} train

if [ $opt_dev_test_size ]; then
#  let offset=${train_size}+1
  let offset=1
  let size=${opt_dev_test_size}*2
  for (( i = 0; i < ${#langs[@]}; i++ )); do
    show_exec tail -n +${offset} ${files[$i]} \| head -n ${size} \> ${corpus}/devtest.${langs[$i]}
#    show_exec tail -n ${size} ${files[$i]} \> ${corpus}/devtest.${langs[$i]}
#  tokenize ${lang1} devtest
#  truecase ${lang1} devtest
    show_exec cat ${corpus}/devtest.${langs[$i]} \| ${dir}/interleave.py ${corpus}/{test,dev}.${langs[$i]}
  done
else
#  let offset=${train_size}+1
  let offset=1
  if [[ "${test_size}" -gt 0 ]]; then
    for (( i = 0; i < ${#langs[@]}; i++ )); do
      show_exec tail -n +${offset} ${files[$i]} \| head -n ${test_size} \> $corpus/test.${langs[$i]}
#  tokenize ${lang1} test
#  truecase ${lang1} test
    done
  fi
  let offset=${offset}+${test_size}
  if [[ "${dev_size}" -gt 0 ]]; then
    for (( i = 0; i < ${#langs[@]}; i++ )); do
#  tokenize ${lang1} dev
#  truecase ${lang1} dev
      show_exec tail -n +${offset} ${files[$i]} \| head -n ${dev_size} \> ${corpus}/dev.${langs[$i]}
    done
  fi
fi

#if [[ "${train_size}" -gt 0 ]]; then
#  show_exec ${TRAVATAR}/script/train/clean-corpus.pl -max_len ${CLEAN_LENGTH} ${corpus}/train.{$lang1,$lang2} ${corpus}/train.clean.{$lang1,$lang2}
#fi

