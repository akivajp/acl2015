#!/usr/bin/env python
# -*- coding: utf-8 -*-

'''phrase table filtering function'''

import argparse
import os
import pprint
import re
import sys
import subprocess

from exp.common import debug
from exp.common import files
from exp.phrasetable import record

pp = pprint.PrettyPrinter()

PV = None
if subprocess.call('which pv > /dev/null', shell = True) == 0:
    PV = 'pv'

env = os.environ.copy()
env['LC_ALL'] = 'C'

def matchRules(rec, rules):
    for rule in rules:
        expr = re.sub('c\.c', str(rec.counts.co), rule)
        #debug.log(expr)
        if eval(expr):
            #print("MATCH")
            pass
        else:
            #print("MISMATCH")
            return False
    return True

def filterTable(srcFile, saveFile, rules, progress, RecordClass = record.MosesRecord):
    if type(srcFile) == str:
      srcFile = files.open(srcFile)
    if type(saveFile) == str:
      if files.getExt(saveFile) == '.gz':
        saveFile = open(saveFile, 'w')
        pipeGzip = subprocess.Popen(['gzip'], stdin=subprocess.PIPE, stdout=saveFile)
        saveFile = pipeGzip.stdin
      else:
        saveFile = open(saveFile, 'w')
    pipePV = None
    if progress and PV:
        cmd = '%s -Wl -N "filtered lines"' % (PV)
        pipePV = subprocess.Popen(cmd, env=env, stdin=subprocess.PIPE, stdout=saveFile, close_fds=True, shell=True)
        output = pipePV.stdin
    else:
        output = saveFile
    for line in srcFile:
      rec = RecordClass(line)
      if matchRules(rec, rules):
          output.write( rec.toStr() )
    if pipePV:
        pipePV.stdin.close()
        pipePV.communicate()
    saveFile.close()

def filterMosesTable(srcFile, saveFile, rules, progress = True):
    filterTable(srcFile, saveFile, rules, progress, record.MosesRecord)

def main():
    epilog = '''
each rule should be as '{varname} {<,<=,==,>=,>} {value}'
varnames:
    c.s : source count
    c.t : target count
    c.c : co-occurrence count
example:
    %s model/phrase-table.gz model/filtered-table.gz 'c.c > 1'
    ''' % sys.argv[0]
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description='filter moses phrase-table by supplied rules',
        epilog = epilog,
    )
    parser.add_argument('srcFile',  help='file path to load phrase-table')
    parser.add_argument('saveFile', help='file path to save phrase-table')
    parser.add_argument('rules', metavar='rule', nargs='+', help='filtering rule to save record')
    parser.add_argument('--progress', '-p', action='store_true',
                        help='show progress bar (pv command should be installed')
    args = vars(parser.parse_args())
    #print(args)
    filterMosesTable(**args)

if __name__ == '__main__':
    main()

