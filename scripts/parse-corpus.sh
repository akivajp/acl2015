#!/bin/bash

dir="$(cd "$(dirname "${BASH_SOURCE:-${(%):-%N}}")"; pwd)"
source "${dir}/common.sh"

usage()
{
  echo "usage: $0 corpus_dir"
  echo ""
  echo "options:"
  echo "  --threads={int}"
}

if [ ${#ARGS[@]} -lt 1 ]
then
  usage
  exit 1
fi

corpus=$1

parse()
{
  model=$1
  input=$2
  output=$3
  lines=$(wc -l $input | cut -d' ' -f1)
#  d=$(expr $lines / $THREADS + 1)
  d=$(expr \( $lines + ${THREADS} - 1 \) / ${THREADS} )
  base=$(basename $input)
  show_exec mkdir -p ${corpus}/tmp
  show_exec split -l ${d} ${input} ${corpus}/tmp/${base}.
  show_exec ls ${corpus}/tmp/${base}.\* \| parallel -j ${THREADS} ${CKYLARK}/src/bin/ckylark --model $1 --input {} --output {}.parsed --add-root-tag
  show_exec cat ${corpus}/tmp/${base}.\*.parsed \> ${output}
}

##if [ -f "${corpus}/train.true.en" ]; then
#if [ -f "${corpus}/train.clean.en" ]; then
#  parse ${CKYLARK}/model/wsj ${corpus}/train.clean.en ${corpus}/train.tree.en
#  parse ${CKYLARK}/model/wsj ${corpus}/test.true.en  ${corpus}/test.tree.en
#  parse ${CKYLARK}/model/wsj ${corpus}/dev.true.en   ${corpus}/dev.tree.en
#fi
#
##if [ -f "${corpus}/train.true.ja" ]; then
#if [ -f "${corpus}/train.clean.ja" ]; then
#  parse ${CKYLARK}/model/jdc ${corpus}/train.clean.ja ${corpus}/train.tree.ja
#  parse ${CKYLARK}/model/jdc ${corpus}/test.true.ja  ${corpus}/test.tree.ja
#  parse ${CKYLARK}/model/jdc ${corpus}/dev.true.ja   ${corpus}/dev.tree.ja
#fi

for lang in en ja; do
  case ${lang} in
    en)
      model=${CKYLARK}/model/wsj
      ;;
    ja)
      model=${CKYLARK}/model/jdc
      ;;
    *)
      echo "cannot solve parsing model"
      exit 1
      ;;
  esac
  if [ -f "${corpus}/train.clean.${lang}" ]; then
    parse ${model} ${corpus}/train.clean.${lang} ${corpus}/train.tree.${lang}
#    parse ${model} ${corpus}/test.true.${lang}   ${corpus}/test.tree.${lang}
    parse ${model} ${corpus}/test.${lang}   ${corpus}/test.tree.${lang}
#    parse ${model} ${corpus}/dev.true.${lang}    ${corpus}/dev.tree.${lang}
    parse ${model} ${corpus}/dev.${lang}    ${corpus}/dev.tree.${lang}
  fi
done

