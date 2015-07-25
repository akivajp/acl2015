#!/usr/bin/env python
# -*- coding: utf-8 -*-

#NBEST = 0
#NBEST = 20
#NBEST = 50
NBEST = 100
NBEST_COUNT = 10

methods = ['countmin', 'prodprob', 'bidirmin', 'bidirgmean', 'bidirmax', 'bidiravr']
METHOD = 'countmin'

import argparse
from exp.phrasetable import lex

#def pivot_lex(lexfile1, lexfile2, savefile, nbest = NBEST):
def pivot_lex(lexfile1, lexfile2, savefile, **options):
    method = options.get('method', 'count')
    if method == 'count':
        nbest = options.get('nbest', NBEST_COUNT)
    else:
        nbest = options.get('nbest', NBEST)
    cntSrcPvt = lex.loadWordPairCounts(lexfile1)
    cntPvtTrg = lex.loadWordPairCounts(lexfile2)
#    cntSrcTrg = lex.pivotWordPairCounts(cntSrcPvt, cntPvtTrg, nbest = nbest)
    cntSrcTrg = lex.pivotWordPairCounts(cntSrcPvt, cntPvtTrg, **options)
    lex.saveWordPairCounts(savefile, cntSrcTrg)

def main():
    parser = argparse.ArgumentParser(description = 'triangulate lex files by co-occurrence counts estimation')
    parser.add_argument('lexfile1', help = 'word pair counts file src->pvt')
    parser.add_argument('lexfile2', help = 'word pair counts file pvt->trg')
    parser.add_argument('savefile', help = 'path for saving word pair counts')
    parser.add_argument('--nbest', type = int, default=NBEST)
    parser.add_argument('--method', choices = methods, default=METHOD)
    args = vars(parser.parse_args())
    pivot_lex(**args)

if __name__ == '__main__':
    main()

