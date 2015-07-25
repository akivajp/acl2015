#!/usr/bin/env python
# -*- coding: utf-8 -*-

'''functions to triangulate 2 phrase tables into 1 table
by combining source-pivot and pivot-target for common pivot phrase'''

import argparse
import codecs
import math
import multiprocessing
import os
import pprint
import sys
import time

from collections import defaultdict

# my exp libs
from exp.common import cache, debug, files, progress
from exp.phrasetable import findutil
from exp.phrasetable import lex, combine_lex
from exp.phrasetable.record import MosesRecord
from exp.phrasetable.reverse import reverseTable

# lower threshold of trans probs to abort
#THRESHOLD = 1e-3
THRESHOLD = 0 # not aborting

# lower guarantee for lexical trans probs
MINPROB = 10 ** -10

# limit number of records for the same source phrase
NBEST = 20

#PIVOT_QUEUE_SIZE = 2000
PIVOT_QUEUE_SIZE = 1000

# methods to estimate trans probs (countmin/prodprob/bidirmin/bidirgmean/bidirmax/bidiravr)
methods = ['countmin', 'prodprob', 'bidirmin', 'bidirgmean', 'bidirmax', 'bidiravr']
#METHOD = 'counts'
#METHOD = 'hybrid'
METHOD = 'countmin'

# methods to estimate lexical weight
lexMethods = ['prodweight', 'countmin', 'prodprob', 'bidirmin', 'bidirgmean', 'bidirmax', 'bidiravr', 'table', 'countmin+table', 'prodprob+table', 'bidirmin+table', 'bidirgmean+table']
LEX_METHOD = 'prodweight'

NULLS = 10**4

NOPREFILTER = False

# cache size for search history of target records
#CACHESIZE = 1000
CACHESIZE = 3000
#CACHESIZE = 5000
#CACHESIZE = 10000

pp = pprint.PrettyPrinter()

class WorkSet:
    '''data set for multi-processing'''
    def __init__(self, savefile, workdir, method, **options):
        prefix = options.get('prefix', 'phrase')
        self.multiTarget = options.get('multiTarget', False)
        self.Record = options.get('RecordClass', MosesRecord)
        self.method = method
#        if method.find('multi') >= 0:
#            self.multiTarget = True
#            self.method = method.replace('multi','').replace('+','')
        self.nbest = NBEST
        self.outQueue = multiprocessing.Queue()
        self.pivotCount = progress.Counter(scaleup = 1000)
        self.pivotQueue = multiprocessing.Queue()
        self.savePath = savefile
        self.threshold = THRESHOLD
        self.workdir = workdir
#        if method == 'prodprob':
#            self.pivotPath = savefile
#        if method in ('counts', 'hybrid'):
#        else:
        self.pivotPath = "%s/%s_pivot" % (workdir, prefix)
        self.revPath = "%s/%s_reversed" % (workdir, prefix)
        self.trgCountPath = "%s/%s_trg" % (workdir, prefix)
        self.revTrgCountPath = "%s/%s_revtrg" % (workdir, prefix)
        self.countPath = "%s/%s_pprobs" % (workdir, prefix)
        self.tableLexPath = '%s/table.lex' % (workdir)
        self.combinedLexPath = '%s/combined.lex' % (workdir)
#        else:
#          assert False, "Invalid method"
        self.pivotProc = multiprocessing.Process( target = pivotRecPairs, args = (self,) )
        self.recordProc = multiprocessing.Process( target = writeRecordQueue, args = (self,) )

    def __del__(self):
        self.close()

    def close(self):
        if self.pivotProc.pid:
            if self.pivotProc.exitcode == None:
                self.pivotProc.terminate()
            self.pivotProc.join()
        if self.recordProc.pid:
            if self.recordProc.exitcode == None:
                self.recordProc.terminate()
            self.recordProc.join()
        self.pivotQueue.close()
        self.outQueue.close()

    def join(self):
        self.pivotProc.join()
        self.recordProc.join()

    def start(self):
        self.pivotProc.start()
        self.recordProc.start()

    def terminate(self):
        self.pivotProc.terminate()
        self.recordProc.terminate()


def updateFeatures(recPivot, recPair, method, multiTarget = False):
    '''update features'''
    features = recPivot.features
    srcFeatures = recPair[0].features
    trgFeatures = recPair[1].features
    if method.find('prodprob') >= 0:
        # multiplying scores and marginalizing
        if not multiTarget:
            for key in ['egfl', 'egfp', 'fgel', 'fgep']:
                features.setdefault(key, 0)
                features[key] += (srcFeatures[key] * trgFeatures[key])
        if multiTarget:
            for key in ['egfp', 'fgep']:
                features.setdefault(key, 0)
                features[key] += (srcFeatures[key] * trgFeatures[key])
#            # P(trg,pvt|src) = P(trg|pvt,src) * P(pvt|src) ~ P(trg|pvt) * P(pvt|src)
#            features['egfp'] = (srcFeatures['egfp'] * trgFeatures['egfp'])
#            # P(src|pvt,trg) ~ P(src|pvt)
#            features['fgep'] = srcFeatures['fgep']
            for key in ['egfl', 'egfp', 'fgel', 'fgep']:
                features['1'+key] = srcFeatures[key]
    else:
        # multiplying only lexical weights and marginalizing
        for key in ['egfl', 'fgel']:
            features.setdefault(key, 0)
            features[key] += (srcFeatures[key] * trgFeatures[key])
    # using 'p' and 'w' of target
    if 'p' in trgFeatures:
        features['p'] = trgFeatures['p']
    if multiTarget:
        if 'w' in trgFeatures:
            features['0w'] = trgFeatures['w']
        if 'w' in srcFeatures:
            features['1w'] = srcFeatures['w']
    else:
        if 'w' in trgFeatures:
            features['w'] = trgFeatures['w']


def updateCounts(recPivot, recPair, method):
    '''update occurrence counts of phrase'''
    counts = recPivot.counts
    features = recPivot.features
    if method == 'countmin':
        #counts.co = max(counts.co, min(recPair[0].counts.co, recPair[1].counts.co))
        #c = recPair[0].counts.co * recPair[1].counts.co
        c = min(recPair[0].counts.co, recPair[1].counts.co)
        counts.co += c
        #counts.co = counts.co + c + 2 * math.sqrt(counts.co * c)
    elif method == 'bidirmin':
        counts1 = recPair[0].counts
        counts2 = recPair[1].counts
        co1 = counts1.co * counts2.co / float(counts2.src)
        co2 = counts2.co * counts1.co / float(counts1.trg)
        counts.co += min(co1, co2)
#        if True:
#        if recPair[0].src.find('Dieu') >= 0:
#            progress.log("%s ||| %s ||| %s ||| (%s %s %s) * (%s %s %s) -> %s %s -> %s\n" % (recPair[0].src, recPair[0].trg, recPair[1].trg, counts1.co, counts1.src, counts1.trg, counts2.co, counts2.src, counts2.trg, co1, co2, min(co1,co2)))
    elif method == 'bidirgmean':
        counts1 = recPair[0].counts
        counts2 = recPair[1].counts
        co1 = counts1.co * counts2.co / float(counts2.src)
        co2 = counts2.co * counts1.co / float(counts1.trg)
        counts.co += math.sqrt(co1*co2)
#        progress.log("%s ||| %s ||| %s ||| (%s %s %s) * (%s %s %s) -> %s %s -> %s\n" % (recPair[0].src, recPair[0].trg, recPair[1].trg, counts1.co, counts1.src, counts1.trg, counts2.co, counts2.src, counts2.trg, co1, co2, math.sqrt(co1*co2)))
    elif method == 'bidirmax':
        counts1 = recPair[0].counts
        counts2 = recPair[1].counts
        co1 = counts1.co * counts2.co / float(counts2.src)
        co2 = counts2.co * counts1.co / float(counts1.trg)
        counts.co += max(co1, co2)
    elif method == 'bidiravr':
        counts1 = recPair[0].counts
        counts2 = recPair[1].counts
        co1 = counts1.co * counts2.co / float(counts2.src)
        co2 = counts2.co * counts1.co / float(counts1.trg)
        counts.co += (co1 + co2) * 0.5
    elif method == 'prodprob':
        counts.src = recPair[0].counts.src
        counts.co  = counts.src * features['egfp']
        counts.trg = counts.co / features['fgep']
    elif method == 'multi':
        c = min(recPair[0].counts.co, recPair[1].counts.co)
        counts.co += c
    else:
        assert False, "Invalid method"


def mergeAligns(recPivot, recPair):
    '''merge word alignments'''
#    if recPivot.aligns:
#      return
#    alignSet = set()
    alignMapSrcPvt = recPair[0].alignMap
    alignMapPvtTrg = recPair[1].alignMap
    for srcIndex, pvtIndices in alignMapSrcPvt.items():
        for pvtIndex in pvtIndices:
            for trgIndex in alignMapPvtTrg.get(pvtIndex, []):
              align = '%d-%d' % (srcIndex, trgIndex)
#              alignSet.add(align)
              recPivot.aligns.add(align)
#    recPivot.aligns = sorted(alignSet)


def filterByCountRatioToMax(records, div = 100):
    coMax = 0
    for rec in flattenRecords(records):
        coMax = max(coMax, rec.counts.co)
    if isinstance(records, list):
        newRecords = []
        for rec in records:
            if rec.counts.co >= coMax / float(div):
                newRecords.append( rec )
        records = newRecords
    elif isinstance(records, dict):
        newRecords = {}
        for key, rec in records.items():
            if rec.counts.co >= coMax / float(div):
                newRecords[key] = rec
        records = newRecords
    return records


def calcPhraseTransProbsByCounts(records):
    '''calculate forward phrase trans probs by occurrence counts of the phrases'''
    srcCount = calcSrcCount(records)
    for rec in records.values():
    #for rec in flattenRecords(records):
        counts = rec.counts
        counts.src = srcCount
        if srcCount > 0:
            rec.features['egfp'] = counts.co / float(srcCount)
        else:
            rec.features['egfp'] == 0


def calcPhraseTransProbsOnTable(tablePath, savePath, **options):
    '''calculate phrase trans probs on the table in which co-occurrence counts are estimated'''
    method = options.get('method', METHOD)
    RecordClass = options.get('RecordClass', MosesRecord)

    tableFile = files.open(tablePath, "r")
    saveFile  = files.open(savePath, "w")
    records = {}
    lastSrc = ''
    for line in tableFile:
        rec = RecordClass(line)
        key = "%s ||| %s |||" % (rec.src, rec.trg)
        if rec.src != lastSrc and records:
            calcPhraseTransProbsByCounts(records)
            writeRecords(saveFile, records)
            records = {}
        if rec.counts.co > 0:
            records[key] = rec
        lastSrc = rec.src
    if records:
        calcPhraseTransProbsByCounts(records)
        writeRecords(saveFile, records)
    saveFile.close()
    tableFile.close()


def calcSrcCount(records):
    '''calculate source phrase occurrence counts by co-occurrence counts'''
    total = 0
    for rec in flattenRecords(records):
        total += rec.counts.co
    return total

def updateWordPairCounts(lexCounts, records):
    '''find word pairs in phrase pairs, and update the counts of word pairs'''
    if len(records) > 0:
        srcSymbols = records.values()[0].srcSymbols
        if len(srcSymbols) == 1:
           for rec in records.values():
               trgSymbols = rec.trgSymbols
               if len(trgSymbols) == 1:
                   lexCounts.addPair(srcSymbols[0], trgSymbols[0], rec.counts.co)
        lexCounts.filterNBestBySrc(srcWord = srcSymbols[0])

def flattenRecords(records, sort = False):
    '''if records are type of dict, return them as a list'''
    if type(records) == dict:
        if sort:
            recordList = []
            for key in sorted(records.keys()):
              recordList.append(records[key])
            return recordList
        else:
            return records.values()
    elif type(records) == list:
        if sort:
            return sorted(records)
        else:
            return records
    else:
        assert False, "Invalid records"

def pivotRecPairs(workset):
    '''combine the source-pivot and pivot-target records for common pivot phrases

    get the list of record pairs in pivotQueue and put the processed data in outQueue

    if workset.method == "prodprob", estimate trans probs by marginalization
    otherwise, calculate them by estimating co-occurrence counts
    '''
    lexCounts = lex.PairCounter()

    while True:
        # get the list of record pairs to pivot
        rows = workset.pivotQueue.get()
        if rows == None:
            # when getting None, finish the process
            break
        records = {}
        if workset.multiTarget:
            multiRecords = {}
        for recPair in rows:
            trgKey = recPair[1].trg + ' |||'
            if workset.multiTarget:
                strMultiTrg = intern(recPair[1].trg + ' |COL| ' + recPair[0].trg)
                multiKey = strMultiTrg + ' |||'
            if not trgKey in records:
                # source-target record not yet exists, so making new record
                recPivot = workset.Record()
                recPivot.src = recPair[0].src
                recPivot.trg = recPair[1].trg
                records[trgKey] = recPivot
            recPivot = records[trgKey]
            if workset.multiTarget:
                recMulti = workset.Record()
                recMulti.src = recPair[0].src
                recMulti.trg = strMultiTrg
                multiRecords[multiKey] = recMulti
            # estimating updated features
            updateFeatures(recPivot, recPair, workset.method)
            # updating the count of phrase pair
            updateCounts(recPivot, recPair, workset.method)
            # merging the word alignments
            mergeAligns(recPivot, recPair)
            if workset.multiTarget:
                updateFeatures(recMulti, recPair, workset.method, multiTarget = True)
                updateCounts(recMulti, recPair, workset.method)
                mergeAligns(recMulti, recPair)
        # at this time, all the source-target records are determined for given source
        if workset.multiTarget:
            # copying the estimated features of source-target records to source-target-pivot records
            for multiKey, recMulti in multiRecords.items():
                trgPair = recMulti.trg.split(' |COL| ')
                recPivot = records[trgPair[0]+' |||']
                for featureKey in ['egfl', 'egfp', 'fgel', 'fgep']:
                    recMulti.features['0'+featureKey] = recPivot.features[featureKey]
        if workset.method != 'prodprob':
            # find word pairs in phrase pairs and update the counts of word pairs
            updateWordPairCounts(lexCounts, records)
            # filtering n-best records by co-occurrence counts
            if not NOPREFILTER:
                if workset.nbest > 0:
                    if len(records) > workset.nbest:
                        scores = []
                        for key, rec in records.items():
                            scores.append( (rec.counts.co, key) )
                        scores.sort(reverse = True)
                        bestRecords = {}
                        for _, key in scores[:workset.nbest]:
                            bestRecords[key] = records[key]
                        records = bestRecords
            # calculate forward phrase trans probs
            calcPhraseTransProbsByCounts(records)
        # if threshold is set (non-zero), aborting the records having trans probs under it
        if workset.threshold < 0:
            # aborting records for extremely small trans probs
            ignoring = []
            for key, rec in records.items():
                if rec[0]['fgep'] < workset.threshold and rec[0]['egfp'] < workset.threshold:
                    ignoring.append(pair)
            for key in ignoring:
                del records[key]
        # if limit number of records is set (non-zero), filter the n-best records by forward trans probs
        if workset.nbest > 0:
            if len(records) > workset.nbest:
                scores = []
                for key, rec in records.items():
                    scores.append( (rec.features['egfp'],key) )
                scores.sort(reverse = True)
                bestRecords = {}
                for _, key in scores[:workset.nbest]:
                    bestRecords[key] = records[key]
                records = bestRecords
            if workset.multiTarget:
                if len(multiRecords) > workset.nbest:
                    # T1-filtering method
                    bestTrgRecords = {}
                    # first, filtering src-pvt-trg records including n-best src-trg records
                    for multiKey, recMulti in multiRecords.items():
                        for rec in records.values():
                            if multiKey.find(rec.trg + ' |COL|') == 0:
                                bestTrgRecords.setdefault(rec.trg, [])
                                bestTrgRecords[rec.trg].append(recMulti)
                    bestMultiRecords = {}
                    # second, filtering n-best by forward joint trans probs
                    for trgKey, multiList in bestTrgRecords.items():
                        bestMultiRec = None
                        bestForwardJointTransProb = 0
                        for multiRec in multiList:
                            if multiRec.features['egfp'] > bestForwardJointTransProb:
                                bestMultiRec = multiRec
                                bestForwardJointTransProb = multiRec.features['egfp']
                        if bestMultiRec:
                            bestMultiRecords[bestMultiRec.trg] = bestMultiRec
                    # filling n-best records by (s->t,s->t,p)
                    scores = []
                    for multiKey, recMulti in multiRecords.items():
                        scores.append( (recMulti.features['0egfp'],recMulti.features['egfp'],multiKey) )
                    scores.sort(reverse = True)
                    for _, _, multiKey in scores:
                        if len(bestMultiRecords) >= workset.nbest:
                            break
                        else:
                            if multiKey in bestMultiRecords:
                                pass
                            else:
                                bestMultiRecords[multiKey] = multiRecords[multiKey]
                    multiRecords = bestMultiRecords
        if workset.multiTarget:
            records = multiRecords
        # putting the records into outQueue, and other process will write them in table file
        if records:
            workset.pivotCount.add( len(records) )
            for trgKey in sorted(records.keys()):
                rec = records[trgKey]
                workset.outQueue.put( rec )
    # exiting from while loop
    # terminate also writeRecords process
    workset.outQueue.put(None)
    if workset.method != 'prodprob':
        lexCounts.filterNBestByTrg()
        lex.saveWordPairCounts(workset.tableLexPath, lexCounts)


def writeRecords(fileObj, records):
#  for rec in flattenRecords(records):
  for rec in flattenRecords(records, sort = True):
      if rec.counts.co > 0:
          fileObj.write( rec.toStr() )


def writeRecordQueue(workset):
    '''write the pivoted records in the queue into the table file'''
    pivotFile = files.open(workset.pivotPath, 'w')
    while True:
        rec = workset.outQueue.get()
        if rec == None:
            # if getting None, finish the loop
            break
        if rec.counts.co > 0:
            pivotFile.write( rec.toStr() )
    pivotFile.close()


class PivotFinder:
    def __init__(self, table1, table2, index1, index2, RecordClass = MosesRecord):
        self.srcFile = files.open(table1, 'r')
        self.trgFile = files.open(table2, 'r')
        self.srcIndices = findutil.loadIndices(index1)
        self.trgIndices = findutil.loadIndices(index2)
        self.srcCount = progress.Counter(scaleup = 1000)
        self.rows = []
        self.rowsCache = cache.Cache(size = CACHESIZE)
        self.Record = RecordClass

    def getRow(self):
        if self.rows == None:
            return None
        while len(self.rows) == 0:
            line = self.srcFile.readline()
            self.srcCount.add()
            if not line:
                self.rows = None
                return None
            self.makePivot(line)
        return self.rows.pop(0)

    def makePivot(self, srcLine):
        recSrc = self.Record(srcLine)
        pivotPhrase = recSrc.trg
        if pivotPhrase in self.rowsCache:
            trgLines = self.rowsCache[pivotPhrase]
            self.rowsCache.use(pivotPhrase)
        else:
            trgLines = findutil.searchIndexed(self.trgFile, self.trgIndices, pivotPhrase)
            self.rowsCache[pivotPhrase] = trgLines
        for trgLine in trgLines:
            recTrg = self.Record(trgLine)
            self.rows.append( [recSrc, recTrg] )

    def close(self):
        self.srcFile.close()
        self.trgFile.close()
        self.rowsCache = None

def calcLexWeight(rec, lexCounts, reverse = False):
#    minProb = 10 ** -2
    lexWeight = 1
#    alignMapRev = rec.alignMapRev
    if not reverse:
        minProb  = 1 / float(lexCounts.trgCounts["NULL"])
        # for forward probs, using reversed alignment map
        alignMap = rec.alignMapRev
        srcTerms = rec.srcTerms
        trgTerms = rec.trgTerms
    else:
        minProb = 1 / float(lexCounts.srcCounts["NULL"])
        alignMap = rec.alignMap
        srcTerms = rec.trgTerms
        trgTerms = rec.srcTerms
    minProb = MINPROB
    for trgIndex in range(len(trgTerms)):
        trgTerm = trgTerms[trgIndex]
        if trgIndex in alignMap:
            trgSumProb = 0
            srcIndices = alignMap[trgIndex]
            for srcIndex in srcIndices:
                srcTerm = srcTerms[srcIndex]
                if not reverse:
                    lexProb = lexCounts.calcLexProb(srcTerm, trgTerm)
                else:
                    lexProb = lexCounts.calcLexProbRev(trgTerm, srcTerm)
                trgSumProb += lexProb
            if type(rec) == MosesRecord:
                trgProb = trgSumProb / len(srcIndices)
            else:
                trgProb = trgSumProb / (len(srcIndices) + 1)
#            lexWeight *= (trgSumProb / len(srcIndices))
        else:
          if not reverse:
#              lexWeight *= lexCounts.calcLexProb("NULL", trgTerm)
              trgProb = lexCounts.calcLexProb("NULL", trgTerm)
          else:
#              lexWeight *= lexCounts.calcLexProb(trgTerm, "NULL")
              trgProb = lexCounts.calcLexProb(trgTerm, "NULL")
        lexWeight *= max(trgProb, minProb)
    return lexWeight

def calcLexWeights(tablePath, lexCounts, savePath, RecordClass = MosesRecord):
    tableFile = files.open(tablePath, 'r')
    saveFile  = files.open(savePath, 'w')
    for line in tableFile:
        rec = RecordClass(line)
        if rec.trg.find('|COL|') < 0:
            rec.features['egfl'] = calcLexWeight(rec, lexCounts, reverse = False)
            rec.features['fgel'] = calcLexWeight(rec, lexCounts, reverse = True)
            saveFile.write( rec.toStr() )
        else:
            rec.features['0egfl'] = calcLexWeight(rec, lexCounts, reverse = False)
            rec.features['0fgel'] = calcLexWeight(rec, lexCounts, reverse = True)
            saveFile.write( rec.toStr() )
    saveFile.close()
    tableFile.close()


def pivot(table1, table2, savefile="phrase-table.gz", workdir=".", **options):
    '''find pair of source-pivot and pivot-target records for common pivot phrase'''
    try:
        # initialize the options
        RecordClass = options.get('RecordClass', MosesRecord)
        prefix = options.get('prefix', 'phrase')
        threshold = options.get('threshold', THRESHOLD)
        alignLexPath   = options.get('alignlex', None)
        nbest     = options.get('nbest', NBEST)
        method    = options.get('method', METHOD)
        lexMethod = options.get('lexmethod', LEX_METHOD)
        numNulls  = options.get('nulls', NULLS)
        multiTarget = options.get('multitarget', False)

        if lexMethod not in ('prodweight', 'table'):
            if alignLexPath == None:
                debug.log(lexMethod)
                assert False, "aligned lexfile is not given"

        # making work directory
        workdir = workdir + '/pivot'
        files.mkdir(workdir)
        # expanding table1
        if files.isGzipped(table1):
            srcWorkTable = "%s/%s_src-pvt" % (workdir, prefix)
            progress.log("table copying into: %s\n" % srcWorkTable)
            files.autoCat(table1, srcWorkTable)
        else:
            srcWorkTable = table1
        # expanding table2
        if files.isGzipped(table2):
            trgWorkTable = "%s/%s_pvt-trg" % (workdir, prefix)
            progress.log("table copying into: %s\n" % trgWorkTable)
            files.autoCat(table2, trgWorkTable)
        else:
            trgWorkTable = table2
        # making index1
        srcIndex = srcWorkTable + '.index'
        progress.log("making index: %s\n" % srcIndex)
        findutil.saveIndices(srcWorkTable, srcIndex)
        # making index2
        trgIndex = trgWorkTable + '.index'
        progress.log("making index: %s\n" % trgIndex)
        findutil.saveIndices(trgWorkTable, trgIndex)
        # making workset
        workOptions = {}
        workOptions['RecordClass'] = RecordClass
        workOptions['prefix'] = prefix
        workOptions['multiTarget'] = multiTarget
#        workset = WorkSet(savefile, workdir, method, RecordClass = RecordClass, prefix = prefix)
        workset = WorkSet(savefile, workdir, method, **workOptions)
        workset.threshold = threshold
        workset.nbest = nbest
        # starting workset
        workset.start()
        # find all the candidates of record pairs
        finder = PivotFinder(srcWorkTable, trgWorkTable, srcIndex, trgIndex, RecordClass = RecordClass)
        currPhrase = ''
        rows = []
        rowCount = 0
        progress.log("beginning pivot\n")
        while True:
            if workset.pivotQueue.qsize() > PIVOT_QUEUE_SIZE:
                time.sleep(1)
            row = finder.getRow()
            if not row:
                break
            rowCount += 1
            srcPhrase = row[0].src
            if currPhrase != srcPhrase and rows:
                # get new target phrase, put the data up to previous phrase
                workset.pivotQueue.put(rows)
                rows = []
                currPhrase = srcPhrase
                #debug.log(workset.record_queue.qsize())
            rows.append(row)
            if finder.srcCount.shouldPrint():
                finder.srcCount.update()
                numSrcRecords = finder.srcCount.count
                ratio = 100.0 * numSrcRecords / len(finder.srcIndices)
                progress.log("source: %d (%3.2f%%), processed: %d, last %s: %s" %
                             (numSrcRecords, ratio, rowCount, prefix, srcPhrase) )
        # exitting from while loop
        # processing the last data
        workset.pivotQueue.put(rows)
        workset.pivotQueue.put(None)
        # waiting for the writing process to finish
        workset.join()
        progress.log("source: %d (100%%), processed: %d, pivot %d  \n" %
                     (finder.srcCount.count, rowCount, workset.pivotCount.count) )
        # closing the workset
        finder.close()
        workset.close()

        # loading necessary word pair count files
        if lexMethod != 'prodweight':
            if lexMethod.find('table') >= 0:
                if lexMethod.find('+') >= 0:
                    progress.log("combining lex counts into: %s\n" % (workset.combinedLexPath))
                    combine_lex.combine_lex(alignLexPath, workset.tableLexPath, workset.combinedLexPath)
                    progress.log("loading combined word trans probabilities\n")
                    lexCounts = lex.loadWordPairCounts(workset.combinedLexPath)
                else:
                    progress.log("loading table lex: %s\n", workset.tableLexPath)
                    lexCounts = lex.loadWordPairCounts(workset.tableLexPath)
                    lexCounts.srcCounts["NULL"] = numNulls
                    lexCounts.trgCounts["NULL"] = numNulls
            else:
                progress.log("loading aligned lex: %s\n" % alignLexPath)
                lexCounts = lex.loadWordPairCounts(alignLexPath)
#        if workset.method == 'countmin':
        if method in ['countmin', 'bidirmin', 'bidirgmean', 'bidirmax', 'bidiravr']:
#            # 単語単位の翻訳確率をロードする
#            #progress.log("loading word trans probabilities\n")
#            #lexCounts = lex.loadWordPairCounts(lexPath)
#            progress.log("combining lex counts into: %s\n" % (workset.combinedLexPath))
#            combine_lex.combine_lex(lexPath, workset.tableLexPath, workset.combinedLexPath)
#            progress.log("loading combined word trans probabilities\n")
#            lexCounts = lex.loadWordPairCounts(workset.combinedLexPath)
            # reversing the table
            progress.log("reversing %s table into: %s\n" % (prefix, workset.revPath) )
            reverseTable(workset.pivotPath, workset.revPath, RecordClass)
            progress.log("reversed %s table\n" % (prefix))
            # calculating backward phrase trans probs for reversed table
            progress.log("calculating reversed phrase trans probs into: %s\n" % (workset.trgCountPath))
            calcPhraseTransProbsOnTable(workset.revPath, workset.trgCountPath, nbest = workset.nbest, RecordClass = RecordClass)
            progress.log("calculated reversed phrase trans probs\n")
            # reverseing the reversed table
#            progress.log("reversing %s table into: %s\n" % (prefix,workset.revTrgCountPath))
            progress.log("reversing %s table into: %s\n" % (prefix,workset.countPath))
#            reverseTable(workset.trgCountPath, workset.revTrgCountPath, RecordClass)
            reverseTable(workset.trgCountPath, workset.countPath, RecordClass)
            progress.log("reversed %s table\n" % (prefix))
            # calculating the forward trans probs
#            progress.log("calculating phrase trans probs into: %s\n" % (workset.countPath))
#            calcPhraseTransProbsOnTable(workset.revTrgCountPath, workset.countPath, nbest = 0, RecordClass = RecordClass)
#            progress.log("calculated phrase trans probs\n")
            if lexMethod != 'prodweight':
                # calculating lexical weights
                progress.log("calculating lex weights into: %s\n" % workset.savePath)
                calcLexWeights(workset.countPath, lexCounts, workset.savePath, RecordClass)
                progress.log("calculated lex weights\n")
            else:
                progress.log("gzipping into: %s\n" % workset.savePath)
                files.autoCat(workset.countPath, workset.savePath)
#        elif method == 'prodprob':
        elif method.find('prodprob') >= 0:
            if lexMethod != 'prodweight':
                # calculating lexical weights
                progress.log("calculating lex weights into: %s\n" % workset.savePath)
                calcLexWeights(workset.pivotPath, lexCounts, workset.savePath, RecordClass)
                progress.log("calculated lex weights\n")
            else:
                progress.log("gzipping into: %s\n" % workset.savePath)
                files.autoCat(workset.pivotPath, workset.savePath)
#        elif method == 'multi':
#                progress.log("gzipping into: %s\n" % workset.savePath)
#                files.autoCat(workset.pivotPath, workset.savePath)
        else:
            assert False, "Invalid method: %s" % method
    except KeyboardInterrupt:
        # catching exception, finish all the workset processes
        print('')
        print('Caught KeyboardInterrupt, terminating all the worker processes')
        workset.close()
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description = 'load 2 phrase tables and pivot into one moses phrase table')
    parser.add_argument('table1', help = 'phrase table 1')
    parser.add_argument('table2', help = 'phrase table 2')
    parser.add_argument('savefile', help = 'path for saving moses phrase table file')
    parser.add_argument('--threshold', help = 'threshold for ignoring the phrase translation probability (real number)', type=float, default=THRESHOLD)
    parser.add_argument('--nbest', help = 'best n scores for phrase pair filtering (default = 20)', type=int, default=NBEST)
    parser.add_argument('--method', help = 'triangulation method', choices=methods, default=METHOD)
    parser.add_argument('--lexmethod', help = 'lexical triangulation method', choices=lexMethods, default=LEX_METHOD)
    parser.add_argument('--workdir', help = 'working directory', default='.')
    parser.add_argument('--alignlex', help = 'word pair counts file', default=None)
    parser.add_argument('--nulls', help = 'number of NULLs (lines) for table lex', type = int, default=NULLS)
    parser.add_argument('--noprefilter', help = 'No pre-filtering', type = bool, default=False)
    args = vars(parser.parse_args())

    if args['noprefilter']:
        NOPREFILTER = args['noprefilter']

    pivot(**args)

if __name__ == '__main__':
    main()

