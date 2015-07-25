#!/usr/bin/env python
# -*- coding: utf-8 -*-

'''functions to triangulate 2 rule tables into 1 table
by combining source-pivot and pivot-target for common pivot rule'''

import argparse

# my exp libs
import exp.phrasetable.triangulate as base
from exp.ruletable.record import TravatarRecord

# lower threshold of trans probs to abort
#THRESHOLD = 1e-3
THRESHOLD = 0 # not aborting

# limit number of records for the same source phrase
#NBEST = 40
NBEST = 20

NULLS = 10**4

# methods to estimate trans probs
methods = base.methods
METHOD = base.METHOD

# methods to estimate lexical weight
lexMethods = base.lexMethods
LEX_METHOD = base.LEX_METHOD

def main():
    parser = argparse.ArgumentParser(description = 'load 2 rule tables and pivot into one travatar rule table')
    parser.add_argument('table1', help = 'rule table 1')
    parser.add_argument('table2', help = 'rule table 2')
    parser.add_argument('savefile', help = 'path for saving travatar rule table file')
    parser.add_argument('--threshold', help = 'threshold for ignoring the phrase translation probability (real number)', type=float, default=THRESHOLD)
    parser.add_argument('--nbest', help = 'best n scores for rule pair filtering (default = 20)', type=int, default=NBEST)
    parser.add_argument('--method', help = 'triangulation method', choices=methods, default=METHOD)
    parser.add_argument('--lexmethod', help = 'lexical triangulation method', choices=lexMethods, default=LEX_METHOD)
    parser.add_argument('--workdir', help = 'working directory', default='.')
    parser.add_argument('--alignlex', help = 'word pair counts file', default=None)
    parser.add_argument('--nulls', help = 'number of NULLs (lines) for table lex', type = int, default=NULLS)
    parser.add_argument('--noprefilter', help = 'No pre-filtering', type = bool, default=False)
    parser.add_argument('--multitarget', help = 'enabling multi target model', action='store_true')
    args = vars(parser.parse_args())

    args['RecordClass'] = TravatarRecord
    args['prefix'] = 'rule'
    base.pivot(**args)

if __name__ == '__main__':
    main()

