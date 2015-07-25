#!/bin/bash

if [ $# -lt 1 ]; then
  echo "usage: $0 file [file ...]"
  exit 1
fi

for file in $*; do
  if [ ! -f "$file" ]; then
    echo "waiting for file: \"${file}\" ..."
  fi
  while [ ! -f "$file" ]; do
    sleep 1
  done
  echo "file exists: \"${file}\""
done

