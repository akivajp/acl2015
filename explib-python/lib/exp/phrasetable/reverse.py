#!/usr/bin/env python
# -*- coding: utf-8 -*-

'''function reversing phrase table'''

import codecs
import gc
import os
import pprint
import subprocess

from exp.common import files
from exp.phrasetable import record

pp = pprint.PrettyPrinter()

PV = None
if subprocess.call('which pv > /dev/null', shell = True) == 0:
    PV = 'pv'

def reverseTable(srcFile, saveFile, RecordClass = record.MosesRecord):
    if type(srcFile) == str:
        srcFile = files.open(srcFile)
    if type(saveFile) == str:
        if files.getExt(saveFile) == '.gz':
            saveFile = open(saveFile, 'w')
            pipeGzip = subprocess.Popen(['gzip'], stdin=subprocess.PIPE, stdout=saveFile)
            saveFile = pipeGzip.stdin
        else:
            saveFile = open(saveFile, 'w')
    gc.collect()
    env = os.environ.copy()
    env['LC_ALL'] = 'C'
    if PV:
        cmd = '%s -Wl -N "loaded lines" | sort | %s -Wl -N "sorted lines"' % (PV, PV)
        pipeSort = subprocess.Popen(cmd, env=env, stdin=subprocess.PIPE, stdout=saveFile, close_fds=True, shell=True)
    else:
        pipeSort = subprocess.Popen(['sort'], env=env, stdin=subprocess.PIPE, stdout=saveFile, close_fds=True)
    #inputSort = codecs.getwriter('utf-8')(pipeSort.stdin)
    inputSort = pipeSort.stdin
    for line in srcFile:
        rec = RecordClass(line)
        inputSort.write( rec.getReversed().toStr() )
    pipeSort.stdin.close()
    pipeSort.communicate()
    saveFile.close()

def reverseMosesTable(srcFile, saveFile):
    reverseTable(srcFile, saveFile, record.MosesRecord)

