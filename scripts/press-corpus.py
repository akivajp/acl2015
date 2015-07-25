#!/usr/bin/python

import sys
import re

def all_eof(lines):
  if len(lines) == 0:
    return True
  for line in lines:
    if line != "":
      return False
  return True

def any_blank(lines):
  for line in lines:
    if re.match('^\s*$', line):
      return True
  return False

def merge(lines, addition):
  merged = []
  if not lines:
    lines = []
  for i, add in enumerate(addition):
    line = ''
    if i < len(lines):
      line = lines[i] + ' '
    merged.append(line + add)
  return merged

def write_lines(outfiles, lines):
  if not any_has_double_dots(lines):
    for i, line in enumerate(lines):
      outfile = outfiles[i]
      outfile.write(line + "\n")

def any_has_double_dots(lines):
  for line in lines:
    if re.search(' \..* \.', line):
      #print("line has double dots: %s" % line)
      return True
  return False


if __name__ == "__main__":
  if len(sys.argv) < 2:
    print("usage: %s corpus1 corpus2 ..." % sys.argv[0])
    sys.exit(1)
  files = sys.argv[1:]
  print("files: %s" % files)
  infiles = []
  outfiles = []
  for filename in files:
    infiles.append(open(filename, 'r'))
    outfiles.append(open(filename + ".out", 'w'))

  count = 0
  merged = []
  while True:
    count += 1
    #print("count: %s" % count)
    #print("merged: %s" % merged)
    lines = []
    all_eof = True
    for infile in infiles:
      line = infile.readline()
      if (line != ""):
        all_eof = False
      line = line.strip()
      lines.append(line)
    #print("lines: %s" % lines)
    if all_eof:
      write_lines(outfiles, merged)
      break
    if any_blank(lines):
      print ("merging[%s]: %s" % (count, lines) )
      merged = merge(merged, lines)
    else:
      write_lines(outfiles, merged)
      merged = lines

