#!/usr/bin/env python
# -*- coding: utf-8 -*-

import sys
import os
import argparse
import glob

def main():
    parser = argparse.ArgumentParser(description = 'merge corpora in xml files and remove tags')
    parser.add_argument('corpus', help = 'input corpus directory')
    parser.add_argument('output', help = 'prefix of output corpus names')
    parser.add_argument('langs', metavar = 'language_code', nargs='+', help = 'list of language codes')
    args = parser.parse_args()

    if (not os.path.isdir(args.corpus)):
        print('corpus dir "%s" is not found' % (args.corpus))
        exit(-1)
    if (not os.path.isdir("%s/%s" % (args.corpus, args.langs[0]))):
        print('corpus dir "%s/%s" is not found' % (args.corpus, args.langs[0]))
        exit(-1)

    outPrefix = args.output
    if outPrefix.endswith('/'):
        try:
            print("make dirs: %s" % args.output)
            os.makedirs(args.output)
        except:
            pass
        outPrefix += str.join('-', args.langs)
    outFiles = []
    for lang in args.langs:
        outname = "%s.%s" % (outPrefix, lang)
        print("opening to write: %s" % outname)
        outFiles.append( open(outname, 'w') )

    files = glob.glob("%s/%s/ep-*.txt" % (args.corpus, args.langs[0]));
    for f in files:
        base = os.path.basename(f)
        inFiles = []
        for lang in args.langs:
            name = "%s/%s/%s" % (args.corpus, lang, base)
            print("opening to read: %s" % name)
            inFiles.append( open(name, 'r') )
        for lines in zip(*inFiles):
            lines = map(str.strip, lines)
            if lines[0][0:1] == '<' and lines[0][-1:None] == '>':
                continue
            for i, line in enumerate(lines):
                outFiles[i].write(line + "\n")
        map(file.close, inFiles)

if __name__ == '__main__':
    main()

