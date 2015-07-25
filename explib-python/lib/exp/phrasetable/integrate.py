#!/usr/bin/env python
# -*- coding: utf-8 -*-

'''function integrating 2 phrase tables having the same language pairs into 1 table'''

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
from exp.phrasetable import lex
from exp.phrasetable import triangulate
from exp.phrasetable.record import MosesRecord
from exp.phrasetable.record import RecordReader
from exp.phrasetable.reverse import reverseTable

# limit number of records for the same source phrase
NBEST = 20

# methods to estiamte translation probs (count/interpolate)
methods = ['count', 'interpolate']
METHOD = 'count'

lexMethods = ['count', 'interpolate']
LEX_METHOD = 'interpolate'

FACTOR_DIRECT = 0.9

pp = pprint.PrettyPrinter()


def integrateTablePair(tablePath1, tablePath2, savePath, **options):
    RecordClass = options.get('RecordClass', MosesRecord)
#    method = options.get('method', 'count')

    recReader1 = RecordReader(tablePath1, **options)
    recReader2 = RecordReader(tablePath2, **options)
    saveFile = files.open(savePath, 'w')

    records1 = recReader1.getRecords()
    records2 = recReader2.getRecords()
    while True:
        if len(records1) == 0 and len(records2) == 0:
            break
        elif len(records1) == 0:
            triangulate.writeRecords(saveFile, records2)
            records2 = recReader2.getRecords()
            continue
        elif len(records2) == 0:
            triangulate.writeRecords(saveFile, records1)
            records1 = recReader1.getRecords()
            continue

        key1 = records1[0].src + ' |||'
        key2 = records2[0].src + ' |||'
        if key1 < key2:
            triangulate.writeRecords(saveFile, records1)
            records1 = recReader1.getRecords()
        elif key1 > key2:
            triangulate.writeRecords(saveFile, records2)
            records2 = recReader2.getRecords()
        else: # key1 == key2
            merged = mergeRecords(records1, records2, **options)
            triangulate.writeRecords(saveFile, merged)
            records1 = recReader1.getRecords()
            records2 = recReader2.getRecords()
    saveFile.close()


def mergeRecords(*recListList, **options):
    RecordClass = options.get('RecordClass', MosesRecord)
    nbest = options.get('nbest', NBEST)
    method = options.get('method', 'count')

    merged = {}
    for records in recListList:
        for recNew in records:
            trgKey = recNew.trg + ' |||'
            if not trgKey in merged:
                recMerge = RecordClass()
                recMerge.src = recNew.src
                recMerge.trg = recNew.trg
                merged[trgKey] = recMerge
                recMerge.features['egfl'] = recNew.features['egfl']
                recMerge.features['fgel'] = recNew.features['fgel']
                if method == 'interpolate':
                    recMerge.features['egfp'] = recNew.features['egfp']
                    recMerge.features['fgep'] = recNew.features['fgep']
            else:
                recMerge = merged[trgKey]
                features = recMerge.features
                F1 = FACTOR_DIRECT
                F2 = 1 - F1
                features['egfl'] = features['egfl'] * F1 + recNew.features['egfl'] * F2
                features['fgel'] = features['fgel'] * F1 + recNew.features['fgel'] * F2
                if method == 'interpolate':
                    features['egfp'] = features['egfp'] * F1 + recNew.features['egfp'] * F2
                    features['fgep'] = features['fgep'] * F1 + recNew.features['fgep'] * F2
            recMerge.counts.co += recNew.counts.co
            recMerge.aligns = set(recMerge.aligns) | set(recNew.aligns)
    if nbest > 0:
        if len(merged) > nbest:
            scores = []
            for key, rec in merged.items():
                if method == 'count':
                    scores.append( (rec.counts.co, key) )
                elif method == 'interpolate':
                    scores.append( (rec.features['egfp'], key) )
                else:
                    assert False, "Invalid method: %s" % method
            scores.sort(reverse = True)
            for count, key in scores[nbest:]:
                del merged[key]
    return merged


def integrate(table1, table2, savefile, **options):
    # initial values of the optiones
    RecordClass = options.get('RecordClass', MosesRecord)
    prefix = options.get('prefix', 'phrase')
    nbest     = options.get('nbest', NBEST)
    workdir   = options.get('workdir', '.')
    lexPath   = options.get('lexfile', None)
    method    = options.get('method', METHOD)
    lexMethod = options.get('lexmethod', LEX_METHOD)

    if lexMethod not in ('interpolate'):
        if lexPath == None:
            debug.log(lexMethod)
            assert False, "aligned lexfile is not given"

    # making work directory
    workdir = workdir + '/integrate'
    files.mkdir(workdir)
    mergePath = "%s/%s_merged" % (workdir, prefix)
    revPath   = "%s/%s_reversed" % (workdir, prefix)
    trgCountPath = "%s/%s_trg" % (workdir, prefix)
    revTrgCountPath = "%s/%s_trgrev" % (workdir, prefix)
    countPath = "%s/%s_pprob" % (workdir, prefix)
    # merging by summing co-occurrence counts
    progress.log("merging records into: %s\n" % mergePath)
    integrateTablePair(table1, table2, mergePath, **options)
    progress.log("merged table\n")
#    # load word translation probabilities
#    progress.log("loading word trans probabilities\n")
#    lexCounts = lex.loadWordPairCounts(lexfile)
    # reversing the table
    if method == 'count':
        progress.log("reversing %s table into: %s\n" % (prefix, revPath) )
        reverseTable(mergePath, revPath, RecordClass)
        progress.log("reversed table\n")
        # estimate backward trans probs for reversed table
        progress.log("calculating reversed phrase trans probs into: %s\n" % (trgCountPath))
        triangulate.calcPhraseTransProbsOnTable(revPath, trgCountPath, RecordClass = RecordClass)
        progress.log("calculated reversed phrase trans probs\n")
        # reversing the table again
        progress.log("reversing %s table into: %s\n" % (prefix,revTrgCountPath))
        reverseTable(trgCountPath, revTrgCountPath, RecordClass)
        progress.log("reversed table\n")
        # estimate forward trans probs
        progress.log("calculating phrase trans probs into: %s\n" % (countPath))
        triangulate.calcPhraseTransProbsOnTable(revTrgCountPath, countPath, RecordClass = RecordClass)
      #  triangulate.calcPhraseTransProbsOnTable(revTrgCountPath, savefile, nbest = 0, RecordClass = RecordClass)
        progress.log("calculated phrase trans probs\n")
        if lexMethod == 'interpolate':
            progress.log("gzipping into: %s\n" % savefile)
            files.autoCat(countPath, savefile)
        else:
            # estimate lexicalized trans probs
            progress.log("calculating lex weights into: %s\n" % workset.savePath)
            calcLexWeights(countPath, lexCounts, savefile, RecordClass)
            progress.log("calculated lex weights\n")
    elif method == 'interpolate':
        if lexMethod == 'interpolate':
            progress.log("gzipping into: %s\n" % savefile)
            files.autoCat(mergePath, savefile)
    else:
        assert False, "Invalid method: %s" % method
#    # extimate lexicalized trans probs
#    progress.log("calculating lex weights into: %s\n" % savefile)
#    triangulate.calcLexWeights(countPath, lexCounts, savefile, RecordClass)
#    progress.log("calculated lex weights\n")


def main():
    parser = argparse.ArgumentParser(description = 'load 2 phrase tables and pivot into one moses phrase table')
    parser.add_argument('table1', help = 'phrase table 1')
    parser.add_argument('table2', help = 'phrase table 2')
    parser.add_argument('savefile', help = 'path for saving moses phrase table file')
    parser.add_argument('--nbest', help = 'best n scores for phrase pair filtering (default = 20)', type=int, default=NBEST)
    parser.add_argument('--workdir', help = 'working directory', default='.')
    parser.add_argument('--lexfile', help = 'word pair counts file', default=None)
    parser.add_argument('--method', help = 'triangulation method', choices=methods, default=METHOD)
    parser.add_argument('--lexmethod', help = 'lexical triangulation method', choices=lexMethods, default=LEX_METHOD)
    args = vars(parser.parse_args())

    integrate(**args)

if __name__ == '__main__':
    main()

