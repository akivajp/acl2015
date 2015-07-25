#!/usr/bin/env python
# -*- coding: utf-8 -*-

import argparse
import glob
import os
import re
import sys

PUNCT = ['.', '!', '?']
ABBR = '(Dr|Mr|Mrs|Ms|Mt|Pres|Prof|Sir)\.$'

def main():
    parser = argparse.ArgumentParser(description = 'merge corpora in xml files and remove tags')
    parser.add_argument('corpus', help = 'input path of mono-lingual corpus directory')
    parser.add_argument('output', help = 'prefix of output corpus names')
    args = parser.parse_args()

    outname = args.output
    if args.output.endswith('/') or os.path.isdir(args.output):
        base = os.path.basename(args.corpus)
        outname = "%s/%s.sent" % (args.output, base)
    print("opening to write: %s" % (outname))
    outFile = open(outname, 'w')

    files = glob.glob("%s/ep-*.txt" % (args.corpus))
    for path in files:
        print("opening to read: %s" % (path))
        inFile = open(path, 'r')
        for line in inFile:
            line = line.strip()
            if not (line[0:1] == '<' and line[-1:None] == '>'):
                inQuot = False
                left = 0
                for i, char in enumerate(line):
                    if char == '"':
                        if line[i+1:i+2] in PUNCT:
                            inQuot = False
                        elif line[i+1:i+2] != ' ':
                            inQuot = True
                        elif line[i-1:i] != ' ':
                            inQuot = False
                    if char in PUNCT and not inQuot:
                        sent = line[left:i+1].strip()
                        if not re.search(ABBR, sent):
                            outFile.write(line[left:i+1].strip() + "\n")
                            left = i + 1
                sent = line[left:None].strip()
                if sent and sent not in PUNCT:
                    outFile.write(sent + "\n")
        inFile.close()
    outFile.close()

if __name__ == '__main__':
    main()

