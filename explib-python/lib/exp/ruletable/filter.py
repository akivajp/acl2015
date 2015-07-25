#!/usr/bin/env python
# -*- coding: utf-8 -*-

'''rule table filtering function'''

import argparse
import sys

from exp.ruletable import record
from exp.phrasetable.filter import filterTable

def filterTravatarTable(srcFile, saveFile, rules, progress = True):
    filterTable(srcFile, saveFile, rules, progress, record.TravatarRecord)

def main():
    epilog = '''
each rule should be as '{varname} {<,<=,==,>=,>} {value}'
varnames:
    c.s : source count
    c.t : target count
    c.c : co-occurrence count
example:
    %s model/rule-table.gz model/filtered-table.gz 'c.c > 1'
    ''' % sys.argv[0]
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description='filter travatar rule-table by supplied rules',
        epilog = epilog,
    )
    parser.add_argument('srcFile',  help='file path to load rule-table')
    parser.add_argument('saveFile', help='file path to save rule-table')
    parser.add_argument('rules', metavar='rule', nargs='+', help='filtering rule to save record')
    parser.add_argument('--progress', '-p', action='store_true',
                        help='show progress bar (pv command should be installed')
    args = vars(parser.parse_args())
    #print(args)
    filterTravatarTable(**args)

if __name__ == '__main__':
    main()

