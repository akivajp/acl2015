#!/bin/bash

if [ $# -lt 1 ]; then
  echo "usage: $0 filepath"
  exit 1
fi

sed -e "s/&amp;/\&/g" -e "s/&apos;/\'/g" -e "s/&lt;/</" -e "s/&gt;/>/" -e "s/-LRB-/\(/g" -e "s/-RRB-/\)/g" $1

