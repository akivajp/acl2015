#!/usr/bin/env python
# -*- coding: utf-8 -*-

import argparse
from exp.phrasetable import lex

def combine_lex(lexfile1, lexfile2, savefile):
    lexCounts1 = lex.loadWordPairCounts(lexfile1)
    lexCounts2 = lex.loadWordPairCounts(lexfile2)
    lexCounts = lex.combineWordPairCounts(lexCounts1, lexCounts2)
    lex.saveWordPairCounts(savefile, lexCounts)

def main():
    parser = argparse.ArgumentParser(description = 'combine lex files by co-occurrence counts estimation')
    parser.add_argument('lexfile1', help = 'word pair counts file 1')
    parser.add_argument('lexfile2', help = 'word pair counts file 2')
    parser.add_argument('savefile', help = 'path for saving word pair counts')
    args = vars(parser.parse_args())
    combine_lex(**args)

if __name__ == '__main__':
    main()

