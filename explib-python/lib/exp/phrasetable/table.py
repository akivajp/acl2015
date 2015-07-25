#!/usr/bin/env python
# -*- coding: utf-8 -*-

'''classes handling phrase table'''

import sys
import time

from exp.common import cache
from exp.common import files
from exp.common import progress
from exp.phrasetable import record

class Table(object):
    def __init__(self, tablePath, RecordClass, **options):
        showProgress = options.get('showProgress', False)
        self.RecordClass = RecordClass
        self.tablePath = tablePath
        self.tableFile = files.open(tablePath, 'r')
        self.recordsSrcTrg = {}
        self.recordsTrgSrc = {}
        self.__load(showProgress)

    def __load(self, showProgress):
        size = files.getContentSize(self.tablePath)
        lastPrint = 0
        for line in self.tableFile:
            rec = self.RecordClass(line)
#            self.recordsSrcTrg.setdefault(rec.src, {})[rec.trg] = rec
            self.recordsSrcTrg.setdefault(rec.src, {})[rec.trg] = None
#            self.recordsTrgSrc.setdefault(rec.trg, {})[rec.src] = rec
            self.recordsTrgSrc.setdefault(rec.trg, {})[rec.src] = None
            if showProgress:
                if time.time() - lastPrint >= 1:
                    lastPrint = time.time()
                    pos = self.tableFile.tell()
                    percentage = pos * 100.0 / size
                    progress.log("Loading \"%s\": %3.2f%% (%s/%s)" % (self.tablePath, percentage, pos, size))
        if showProgress:
            progress.log("Loaded \"%s\": 100%%                          \n" % self.tablePath)

class MosesTable(Table):
    def __init__(self, tablePath, showProgress = False, **options):
        Table.__init__(self, tablePath, record.MosesRecord, showProgress = showProgress, **options)

