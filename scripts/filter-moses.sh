#!/bin/bash

MOSES=$HOME/exp/moses
BIN=$HOME/usr/local/bin

dir=$(cd $(dirname $0); pwd)

THREADS=10

usage()
{
  echo "usage: $0 path/to/moses.ini test_input outdir"
}

show_exec()
{
  echo "[exec] $*"
  eval $*

  if [ $? -gt 0 ]
  then
    echo "[error on exec]: $*"
    exit 1
  fi
}

proc_args()
{
  ARGS=()
  OPTS=()

  while [ $# -gt 0 ]
  do
    arg=$1
    case $arg in
      --*=* )
        opt=${arg#--}
        name=${opt%=*}
        var=${opt#*=}
        eval "opt_${name}=${var}"
        ;;
      -* )
        OPTS+=($arg)
        ;;
      * )
        ARGS+=($arg)
        ;;
    esac

    shift
  done
}

proc_args $*

if [ ${#ARGS[@]} -lt 3 ]
then
  usage
  exit 1
fi

moses_ini=${ARGS[0]}
text=${ARGS[1]}
outdir=${ARGS[2]}

#show_exec mkdir -p ${outdir}
show_exec ${MOSES}/scripts/training/filter-model-given-input.pl ${outdir} ${moses_ini} ${text} -Binarizer ${BIN}/processPhraseTable

