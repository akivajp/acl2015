#!/usr/bin/env python
# -*- coding: utf-8 -*-

import sys

def usage():
  print("usage: %s output1 [output2, ...]" % sys.argv[0])
  sys.exit(1)

if __name__ == '__main__':
  if len(sys.argv) < 2:
    usage()
  files = sys.argv[1:]
  fobjs = []
  for f in files:
    fobjs.append( open(f, 'w') )
  i = 0
  for line in sys.stdin:
    fobjs[i].write(line)
    i = (i + 1) % len(fobjs)

