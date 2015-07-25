#!/usr/bin/env python
# -*- coding: utf-8 -*-

'''functions for controlling the word translation table'''

import codecs
import math
import pprint
import sys
from collections import defaultdict

from exp.common import cache
from exp.common import files
from exp.common import number
from exp.common import progress
from exp.phrasetable import record

stdout = codecs.getwriter('utf-8')(sys.stdout)
pp = pprint.PrettyPrinter()

#NBEST = 50
#NBEST = 10
NBEST = 100

# for integer approximation
MARGIN = 0.0001

# countmin/prodprob/bidirmin/bidirgmean/bidirmax/bidiravr
methods = ['countmin', 'prodprob', 'bidirmin', 'bidirgmean', 'bidirmax', 'bidiravr']
METHOD = 'countmin'

class PairCounter(object):
    def __init__(self):
        self.srcCounts  = defaultdict(int)
        self.trgCounts  = defaultdict(int)
        self.pairCounts  = defaultdict(int)
        self.srcAligned  = defaultdict(set)
        self.trgAligned  = defaultdict(set)

    def addSrc(self, word, count = 1):
        self.srcCounts[word] += count
    def setSrc(self, word, count):
        self.srcCounts[word] = count

    def addTrg(self, word, count = 1):
        self.trgCounts[word] += count
    def setTrg(self, word, count):
        self.trgCounts[word] = count

    def addPair(self, srcWord, trgWord, count = 1):
        self.pairCounts[(srcWord, trgWord)] += count
        self.srcAligned[trgWord].add(srcWord)
        self.trgAligned[srcWord].add(trgWord)
        self.addSrc(srcWord, count)
        self.addTrg(trgWord, count)

    def addNull(self, count = 1):
        self.addSrc(intern("NULL"),count)
        self.addTrg(intern("NULL"),count)

    def calcLexProb(self, srcWord, trgWord):
        coCount = self.pairCounts[(srcWord,trgWord)]
        if coCount == 0:
            if srcWord in self.srcCounts:
                return 1 / float(self.srcCounts[srcWord])
            else:
                return 0
        else:
            return coCount / float(self.srcCounts[srcWord])

    def calcLexProbRev(self, srcWord, trgWord):
        coCount = self.pairCounts[(srcWord,trgWord)]
        if coCount == 0:
            if trgWord in self.trgCounts:
                return 1 / float(self.trgCounts[trgWord])
            else:
                return 0
        else:
            return coCount / float(self.trgCounts[trgWord])

    def delPair(self, srcWord, trgWord):
        if (srcWord, trgWord) in self.pairCounts:
            count = self.pairCounts[srcWord,trgWord]
            del self.pairCounts[srcWord,trgWord]
            self.srcAligned[trgWord].discard(srcWord)
            self.trgAligned[srcWord].discard(trgWord)
            self.srcCounts[srcWord] -= count
            if self.srcCounts[srcWord] <= 0:
                del self.srcCounts[srcWord]
            if self.trgCounts[trgWord] <= 0:
                del self.trgCounts[trgWord]

    def filterNBestBySrc(self, nbest = NBEST, srcWord = None):
        if nbest > 0:
            scores = []
            if srcWord:
                for trgWord in self.trgAligned[srcWord]:
                    scores.append( (self.pairCounts[srcWord, trgWord], trgWord) )
                scores.sort(reverse = True)
                for _, trgWord in scores[nbest:None]:
                    self.delPair(srcWord, trgWord)
            else:
                for srcWord in self.srcCounts.keys():
                    if srcWord != "NULL":
                        self.filterNBestBySrc(nbest, srcWord)

    def filterNBestByTrg(self, nbest = NBEST, trgWord = None):
        if nbest > 0:
            scores = []
            if trgWord:
                for srcWord in self.srcAligned[trgWord]:
                    scores.append( (self.pairCounts[srcWord, trgWord], srcWord) )
                scores.sort(reverse = True)
                for _, srcWord in scores[nbest:None]:
                    self.delPair(srcWord, trgWord)
            else:
                for trgWord in self.trgCounts.keys():
                    if trgWord != "NULL":
                        self.filterNBestByTrg(nbest, trgWord)


def calcWordPairCountsByAligns(srcTextPath, trgTextPath, alignPath):
    srcTextFile = files.open(srcTextPath, 'r')
    trgTextFile = files.open(trgTextPath, 'r')
    alignFile = files.open(alignPath, 'r')
    pairCounter = PairCounter()
    while True:
        srcLine = srcTextFile.readline()
        trgLine = trgTextFile.readline()
        alignLine = alignFile.readline()
        if srcLine == "":
            break
        srcWords = srcLine.strip().split(' ')
        trgWords = trgLine.strip().split(' ')
        alignList = alignLine.strip().split(' ')
#        pairCounter.addNull()
#        for word in srcWords:
#          pairCounter.addSrc(word)
#        for word in trgWords:
#          pairCounter.addTrg(word)
        srcAlignedIndices = set()
        trgAlignedIndices = set()
        for align in alignList:
            (srcIndex, trgIndex) = map(int, align.split('-'))
            srcWord = srcWords[srcIndex]
            trgWord = trgWords[trgIndex]
            pairCounter.addPair(srcWord, trgWord)
            srcAlignedIndices.add( srcIndex )
            trgAlignedIndices.add( trgIndex )
        for i, srcWord in enumerate(srcWords):
            if not i in srcAlignedIndices:
                pairCounter.addPair(srcWord, "NULL")
        for i, trgWord in enumerate(trgWords):
            if not i in trgAlignedIndices:
                pairCounter.addPair("NULL", trgWord)
    return pairCounter


def saveWordPairCounts(savePath, pairCounter):
    saveFile = files.open(savePath, 'w')
    for pair in sorted(pairCounter.pairCounts.keys()):
        srcWord = pair[0]
        trgWord = pair[1]
        srcCount = number.toNumber(pairCounter.srcCounts[srcWord], MARGIN)
        trgCount = number.toNumber(pairCounter.trgCounts[trgWord], MARGIN)
        pairCount = number.toNumber(pairCounter.pairCounts[pair], MARGIN)
        if pairCount > 0:
            buf = "%s %s %s %s %s\n" % (srcWord, trgWord, pairCount, srcCount, trgCount)
        saveFile.write( buf )
    saveFile.close()


def loadWordPairCounts(lexPath):
    lexFile = files.open(lexPath, 'r')
    pairCounter = PairCounter()
    for line in lexFile:
      fields = line.split()
      srcWord = intern( fields[0] )
      trgWord = intern( fields[1] )
#      pairCounter.addPair(srcWord, trgWord, int(fields[2]))
      pairCounter.addPair(srcWord, trgWord, number.toNumber(fields[2]))
#      pairCounter.setSrc(srcWord, number.toNumber(fields[3]))
#      pairCounter.setTrg(trgWord, number.toNumber(fields[4]))
    return pairCounter


def pivotWordPairCounts(cntSrcPvt, cntPvtTrg, **options):
    nbest  = options.get('nbest', 0)
    method = options.get('method', METHOD)
    cntSrcTrg = PairCounter()
    for srcWord in cntSrcPvt.srcCounts.keys():
        for pvtWord in cntSrcPvt.trgAligned[srcWord]:
#            if False and pvtWord == "NULL":
#                # NULL can't be a pivot
#                pass
#                continue
#            if pvtWord == "NULL":
#                count = cntSrcPvt.pairCounts[(srcWord,"NULL")]
#                cntSrcTrg.addPair(srcWord, "NULL", count)
            for trgWord in cntPvtTrg.trgAligned[pvtWord]:
#                if pvtWord == "NULL":
#                    count = cntPvtTrg.pairCounts[("NULL",trgWord)]
#                    cntSrcTrg.addPair("NULL", trgWord, count)
#                    continue
                if srcWord == "NULL" and trgWord == "NULL":
                    # NULL-NULL are not aligned.
                    pass
                else:
                    coCount1 = cntSrcPvt.pairCounts[(srcWord,pvtWord)]
                    coCount2 = cntPvtTrg.pairCounts[(pvtWord,trgWord)]
                    srcCount1 = cntSrcPvt.srcCounts[srcWord]
                    srcCount2 = cntPvtTrg.srcCounts[pvtWord]
                    trgCount1 = cntSrcPvt.trgCounts[pvtWord]
                    trgCount2 = cntPvtTrg.trgCounts[trgWord]
                    if method == 'countmin':
                        count1 = cntSrcPvt.pairCounts[(srcWord,pvtWord)]
                        count2 = cntPvtTrg.pairCounts[(pvtWord,trgWord)]
                        minCount = min(count1, count2)
                        cntSrcTrg.addPair(srcWord, trgWord, minCount)
                    elif method == 'prodprob':
                        probSrcPvt = coCount1 / float(srcCount1)
                        probPvtTrg = coCount2 / float(srcCount2)
                        probSrcTrg = probSrcPvt * probPvtTrg
                        coCount = srcCount1 * probSrcTrg
                        cntSrcTrg.addPair(srcWord, trgWord, coCount)
                    elif method == 'bidirmin':
                        co1 = coCount1 * coCount2 / float(srcCount2)
                        co2 = coCount2 * coCount1 / float(trgCount1)
                        cntSrcTrg.addPair(srcWord, trgWord, min(co1,co2))
                    elif method == 'bidirgmean':
                        co1 = coCount1 * coCount2 / float(srcCount2)
                        co2 = coCount2 * coCount1 / float(trgCount1)
                        cntSrcTrg.addPair(srcWord, trgWord, math.sqrt(co1*co2))
                    elif method == 'bidirmax':
                        co1 = coCount1 * coCount2 / float(srcCount2)
                        co2 = coCount2 * coCount1 / float(trgCount1)
                        cntSrcTrg.addPair(srcWord, trgWord, max(co1,co2))
                    elif method == 'bidiravr':
                        co1 = coCount1 * coCount2 / float(srcCount2)
                        co2 = coCount2 * coCount1 / float(trgCount1)
                        cntSrcTrg.addPair(srcWord, trgWord, (co1 + co2) * 0.5)
                    else:
                        assert False, "Invalid method: %s" % method
            # filtering n-best records by source-side
            if nbest > 0:
                if srcWord != "NULL":
                    cntSrcTrg.filterNBestBySrc(nbest, srcWord)
    # filtering n-best records by target-side
    if nbest > 0:
        cntSrcTrg.filterNBestByTrg(nbest)
    return cntSrcTrg


def combineWordPairCounts(lexCounts1, lexCounts2, **options):
    nbest = options.get('nbest', NBEST)
    lexCounts = PairCounter()
    for pair, count in lexCounts1.pairCounts.items():
        lexCounts.addPair(pair[0], pair[1], count)
#        lexCounts.addSrc(pair[0], count)
#        lexCounts.addTrg(pair[1], count)
    for pair, count in lexCounts2.pairCounts.items():
        lexCounts.addPair(pair[0], pair[1], count)
#        lexCounts.addSrc(pair[0], count)
#        lexCounts.addTrg(pair[1], count)
    if nbest > 0:
        lexCounts.filterNBestBySrc(nbest)
        lexCounts.filterNBestByTrg(nbest)
    return lexCounts


def extractLexRec(srcFile, saveFile, RecordClass = record.MosesRecord):
    if type(srcFile) == str:
        srcFile = files.open(srcFile)
    if type(saveFile) == str:
        saveFile = files.open(saveFile, 'w')
    srcCount = defaultdict(lambda: 0)
    trgCount = defaultdict(lambda: 0)
    coCount  = defaultdict(lambda: 0)
    for line in srcFile:
        rec = record.TravatarRecord(line)
        srcSymbols = rec.srcSymbols
        trgSymbols = rec.trgSymbols
        if len(srcSymbols) == 1 and len(trgSymbols) == 1:
            src = srcSymbols[0]
            trg = trgSymbols[0]
            srcCount[src] += rec.counts.co
            trgCount[trg] += rec.counts.co
            coCount[(src,trg)] += rec.counts.co
    for pair in sorted(coCount.keys()):
        (src,trg) = pair
        egfl = coCount[pair] / float(srcCount[src])
        fgel = coCount[pair] / float(trgCount[trg])
        buf = "%s %s %s %s\n" % (src, trg, egfl, fgel)
        saveFile.write(buf)
    saveFile.close()


def loadWordProbs(srcFile, reverse = False):
    if type(srcFile) == str:
        srcFile = files.open(srcFile)
    probs = {}
    for line in srcFile:
        fields = line.strip().split()
        src = fields[0]
        trg = fields[1]
        if not reverse:
            probs[(src, trg)] = float(fields[2])
        else:
            probs[(trg, src)] = float(fields[3])
    return probs

