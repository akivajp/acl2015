#!/usr/bin/env python
# -*- coding: utf-8 -*-

import sys

def saveIndices(tablePath, indexPath):
    tableFile = open(tablePath, 'r')
    indexFile = open(indexPath, 'w')
    while True:
        pos = tableFile.tell()
        if tableFile.readline() == '':
            break
        indexFile.write("%s\n" % pos)

def makeIndices(tablePath):
    tableFile = open(tablePath, 'r')
    indices = []
    while True:
        pos = fobj.tell()
        if tableFile.readline() == '':
            break
        indices.append( pos )
    return indices

def loadIndices(indexPath):
    indexFile = open(indexPath, 'r')
    indices = []
    for line in indexFile:
        indices.append( int(line.strip()) )
    return indices

def getRecLine(tableFile, indices, index):
    pos = indices[index]
    tableFile.seek(pos)
    return tableFile.readline().strip()

def getKey(recLine):
    fields = recLine.split('|||')
    return fields[0].strip() + ' |||'

def getCommon(tableFile, indices, index):
    '''return the list of records having the common phrase with given index'''
    recLine = getRecLine(tableFile, indices, index)
    src = getKey(recLine)
    recLines = [ recLine ]
    i = 1
    while True:
        if index - i < 0:
            break
        recLine = getRecLine(tableFile, indices, index - i)
        if getKey(recLine) == src:
            recLines.insert(0, recLine)
            i += 1
        else:
            break
    i = 1
    while True:
        if index + i >= len(indices):
            break
        recLine = getRecLine(tableFile, indices, index + i)
        if getKey(recLine) == src:
            recLines.append(recLine)
            i += 1
        else:
            break
    return recLines

def searchIndexed(tableFile, indices, srcPhrase):
    # search key should be "srcPhrase |||"
    key = srcPhrase + ' |||'
    def binsearch(start, end):
        #print(start, end, src_phrase, len(indices) )
        if start > end or start < 0 or end >= len(indices):
            return []
        if start == end:
            recLine = getRecLine(tableFile, indices, start)
            if getKey(recLine) == key:
                return getCommon(tableFile, indices, start)
            else:
                return []
        mid = (start + end) / 2
        midRec = getRecLine(tableFile, indices, mid)
        midKey = getKey(midRec)
        #print("MID = %d: %s" % (mid, mid_key))
        if midKey == key:
            return getCommon(tableFile, indices, mid)
        elif midKey < key:
            return binsearch(mid + 1, end)
        else:
            return binsearch(start, mid - 1)
    return binsearch(0, len(indices) - 1)


def main():
    indexFile = open(sys.argv[2])
    indices = loadIndices(indexFile)
    found = searchIndexed(open(sys.argv[1]), indices, sys.argv[3])
    print(found)

if __name__ == '__main__':
    main()

