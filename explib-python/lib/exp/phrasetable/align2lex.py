#!/usr/bin/env python
# -*- coding: utf-8 -*-

import argparse
from exp.phrasetable import lex

def align2lex(src, trg, align, savefile):
    pairCounter = lex.calcWordPairCountsByAligns(src, trg, align)
    lex.saveWordPairCounts(savefile, pairCounter)

def main():
    parser = argparse.ArgumentParser(description = 'calculate aligned word pair counts by corpus and alignment file')
    parser.add_argument('src', help = 'source language corpus')
    parser.add_argument('trg', help = 'target language corpus')
    parser.add_argument('align', help = 'alignment file')
    parser.add_argument('savefile', help = 'path for saving word pair counts')
    args = vars(parser.parse_args())
    align2lex(**args)

if __name__ == '__main__':
    main()

