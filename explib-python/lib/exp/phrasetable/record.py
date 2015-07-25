#!/usr/bin/env python
# -*- coding: utf-8 -*-

'''classes handling phrase table records'''

from exp.common import cache
from exp.common import debug
from exp.common import files
from exp.common import number

class CoOccurrence(object):
    def __init__(self, src = 0, trg = 0, co = 0):
        self.src = src
        self.trg = trg
        self.co  = co

    # calculate P(e|f) (src -> trg)
    def calcEGFP(self):
        return co / float(src)
    egfp = property(calcEGFP)

    # calculate P(f|e) (trg -> src)
    def calcFGEP(self):
        return co / float(trg)
    fgep = property(calcFGEP)

    def getReversed(self):
        return CoOccurrence(self.trg, self.src, self.co)

    def setCounts(self, src = None, trg = None, co = None):
        if src:
            self.src = src
        if trg:
            self.trg = trg
        if co:
            self.co = co

    def simplify(self, margin = 0):
        '''cast to equivalent integer value if possible'''
#        self.src = getNumber(self.src, margin)
        self.src = number.toNumber(self.src, margin)
#        self.trg = getNumber(self.trg, margin)
        self.trg = number.toNumber(self.trg, margin)
#        self.co  = getNumber(self.co,  margin)
        self.co  = number.toNumber(self.co,  margin)

    def __str__(self):
        name = self.__class__.__name__
        mod  = self.__class__.__module__
        return "%s.%s(src = %s, trg = %s, co = %s)" % (mod, name, src, trg, co)

class Record(object):
    def __init__(self):
      self.src = ""
      self.trg = ""
      self.features = {}
      self.counts = CoOccurrence()
#      self.aligns = []
      self.aligns = set()

    def getAlignMap(self):
        return getAlignMap(self.aligns, reverse = False)
    alignMap = property(getAlignMap)

    def getAlignMapRev(self):
        return getAlignMap(self.aligns, reverse = True)
    alignMapRev = property(getAlignMapRev)

    def getReversed(self):
        recRev = self.__class__()
        recRev.src = self.trg
        recRev.trg = self.src
        recRev.counts = self.counts.getReversed()
#        debug.log(self.toStr())
#        debug.log(self.aligns)
#        recRev.aligns = getRevAligns(self.aligns)
        recRev.aligns = getRevAlignSet(self.aligns)
        revFeatures = {}
        if 'egfp' in self.features:
            revFeatures[intern('fgep')] = self.features['egfp']
        if 'egfl' in self.features:
            revFeatures[intern('fgel')] = self.features['egfl']
        if 'fgep' in self.features:
            revFeatures[intern('egfp')] = self.features['fgep']
        if 'fgel' in self.features:
            revFeatures[intern('egfl')] = self.features['fgel']
        if 'p' in self.features:
            revFeatures[intern('p')] = self.features['p']
        revFeatures[intern('w')] = len(self.srcTerms)
        recRev.features = revFeatures
        return recRev


class MosesRecord(Record):
    def __init__(self, line = "", split = '|||'):
        Record.__init__(self)
        self.split = split
        self.loadLine(line, split)

    def loadLine(self, line, split = '|||'):
        if line:
            fields = line.strip().split(split)
            self.src = intern( fields[0].strip() )
            self.trg = intern( fields[1].strip() )
            self.features = getMosesFeatures(fields[2])
#            self.aligns = fields[3].strip().split()
            self.aligns = getAlignSet( fields[3] )
            listCounts = getCounts(fields[4])
            self.counts.setCounts(trg = listCounts[0], src = listCounts[1], co = listCounts[2])

    def getSrcSymbols(self):
        return self.src.split(' ')
    srcSymbols = property(getSrcSymbols)

    def getSrcTerms(self):
        return self.src.split(' ')
    srcTerms = property(getSrcTerms)

    def getTrgSymbols(self):
        return self.trg.split(' ')
    trgSymbols = property(getTrgSymbols)

    def getTrgTerms(self):
        return self.trg.split(' ')
    trgTerms = property(getTrgTerms)

    def toStr(self, s = ' ||| '):
        strFeatures = getStrMosesFeatures(self.features)
#        strAligns = str.join(' ', self.aligns)
        strAligns = str.join(' ', sorted(self.aligns) )
        self.counts.simplify(0.0001)
        strCounts   = "%s %s %s" % (self.counts.trg, self.counts.src, self.counts.co)
        buf = str.join(s, [self.src, self.trg, strFeatures, strAligns, strCounts]) + "\n"
#        buf = str.join(s, [str(self.src), str(self.trg), strFeatures, strAligns, strCounts]) + "\n"
        return buf


class RecordReader(object):
    def __init__(self, tablePath, **options):
        self.RecordClass = options.get('RecordClass', MosesRecord)
        self.tableFile = files.open(tablePath, 'r')
        self.records = []

    def getRecords(self):
        line = self.tableFile.readline()
        if line == "":
            records = self.records
            self.records = []
            return records
        while line:
            rec = self.RecordClass(line)
            if len(self.records) == 0:
                self.records.append(rec)
            elif rec.src == self.records[0].src:
                self.records.append(rec)
            else:
                records = self.records
                self.records = [rec]
                return records
            line = self.tableFile.readline()
        records = self.records
        self.records = []
        return records


def getAlignMap(aligns, reverse = False):
    alignMap = {}
    for align in aligns:
        (s, t) = map(int, align.split('-'))
        if reverse:
            alignMap.setdefault(t, []).append(s)
        else:
            alignMap.setdefault(s, []).append(t)
    return alignMap

def getAlignSet(strField):
    return set(strField.strip().split())

def getCounts(field):
#    return map(getNumber, field.split())
    return map(number.toNumber, field.split())

def getNumber(anyNum, margin = 0):
    numFloat = float(anyNum)
    numInt = int(round(numFloat))
    if margin > 0:
        if abs(numInt - numFloat) < margin:
            return numInt
        else:
            return numFloat
    elif numFloat == numInt:
        return numInt
    else:
        return numFloat

#def getRevAligns(aligns):
def getRevAlignSet(aligns):
#    revAlignList = []
    revAlignSet = set()
#    debug.log(aligns)
    for a in aligns:
      (s, t) = map(int, a.split('-'))
#      revAlignList.append( "%d-%d" % (t, s) )
      revAlignSet.add( "%d-%d" % (t, s) )
#    return sorted(revAlignList)
    return sorted(revAlignSet)


def getMosesFeatures(field):
    features = {}
    scores = map(getNumber, field.split())
    features[intern('fgep')] = scores[0]
    features[intern('fgel')] = scores[1]
    features[intern('egfp')] = scores[2]
    features[intern('egfl')] = scores[3]
    return features

def getStrMosesFeatures(dicFeatures):
    '''convert back the feature dictionary to score string separated by space'''
    scores = []
    scores.append( dicFeatures.get('fgep', 0) )
    scores.append( dicFeatures.get('fgel', 0) )
    scores.append( dicFeatures.get('egfp', 0) )
    scores.append( dicFeatures.get('egfl', 0) )
    return str.join(' ', map(str,scores))

