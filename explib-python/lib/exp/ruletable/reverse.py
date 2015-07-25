#!/usr/bin/env python
# -*- coding: utf-8 -*-

'''function reversing rule table'''

import argparse

from exp.ruletable import record
from exp.phrasetable.reverse import reverseTable

def reverseTravatarTable(srcFile, saveFile):
    reverseTable(srcFile, saveFile, record.TravatarRecord)

def main():
#    parser = argparse.ArgumentParser(description = 'load 2 phrase tables and pivot into one moses phrase table')
    parser = argparse.ArgumentParser()
    parser.add_argument('src_table', help = 'source rule table')
    parser.add_argument('save_table', help = 'save path')
    args = vars(parser.parse_args())

    reverseTravatarTable(args['src_table'], args['save_table'])

if __name__ == '__main__':
    main()

