#!/usr/bin/env python
# -*- coding: utf-8 -*-

'''ルールテーブルのレコードを扱うクラス'''

import math

from exp.common import cache
from exp.phrasetable import record

class TravatarRecord(record.Record):
  def __init__(self, line = "", split = '|||'):
    record.Record.__init__(self)
    self.split = split
    self.loadLine(line, split)

  def loadLine(self, line, split = '|||'):
    if line:
      fields = line.strip().split(split)
      self.src = intern( fields[0].strip() )
      self.trg = intern( fields[1].strip() )
      self.features = getTravatarFeatures(fields[2])
      listCounts = record.getCounts(fields[3])
      self.counts.setCounts(co = listCounts[0], src = listCounts[1], trg = listCounts[2])
#      self.aligns = fields[4].strip().split()
      self.aligns = record.getAlignSet( fields[4] )

  def getSrcSymbols(self):
    return getTravatarSymbols(self.src)
  srcSymbols = property(getSrcSymbols)

  def getSrcTerms(self):
    return getTravatarTerms(self.src)
  srcTerms = property(getSrcTerms)

  def getTrgSymbols(self):
    return getTravatarSymbols(self.trg)
  trgSymbols = property(getTrgSymbols)

  def getTrgTerms(self):
    return getTravatarTerms(self.trg)
  trgTerms = property(getTrgTerms)

  def toStr(self, s = ' ||| '):
    strFeatures = getStrTravatarFeatures(self.features)
    strCounts   = "%s %s %s" % (self.counts.co, self.counts.src, self.counts.trg)
#    strAligns = str.join(' ', self.aligns)
    strAligns = str.join(' ', sorted(self.aligns))
    buf = str.join(s, [self.src, self.trg, strFeatures, strCounts, strAligns]) + "\n"
    return buf

  def getReversed(self):
    recRev = TravatarRecord()
    recRev.src = self.trg
    recRev.trg = self.src
    recRev.counts = self.counts.getReversed()
#    recRev.aligns = record.getRevAligns(self.aligns)
    recRev.aligns = record.getRevAlignSet(self.aligns)
    revFeatures = {}
    if 'egfp' in self.features:
      revFeatures['fgep'] = self.features['egfp']
    if 'egfl' in self.features:
      revFeatures['fgel'] = self.features['egfl']
    if 'fgep' in self.features:
      revFeatures['egfp'] = self.features['fgep']
    if 'fgel' in self.features:
      revFeatures['egfl'] = self.features['fgel']
    if 'p' in self.features:
      revFeatures['p'] = self.features['p']
    revFeatures['w'] = len(self.srcTerms)
    recRev.features = revFeatures
    return recRev


def getTravatarSymbols(rule):
  symbols = []
  for s in rule.split(' '):
    if len(s) < 2:
      if s == "@":
        break
    elif s[0] == '"' and s[-1] == '"':
      symbols.append(s[1:-1])
    elif s[0] == 'x' and s[1].isdigit():
      if len(s) > 3:
        symbols.append('[%s]' % s[3:])
      else:
        symbols.append('[X]')
  return symbols

def getTravatarTerms(rule):
  terms = []
  for s in rule.split(' '):
    if len(s) < 2:
      if s == "@":
        break
    elif s[0] == '"' and s[-1] == '"':
      terms.append(s[1:-1])
  return terms

def getStrTravatarFeatures(dicFeatures):
  '''素性辞書を、'key=val' という文字列で表したリストに変換する'''
  featureList = []
  for key, val in dicFeatures.items():
#    if key in ['egfl', 'egfp', 'fgel', 'fgep']:
#    if key not in ['p', 'w', '0w', '1w']:
    if len(key) >= 4:
      try:
        val = math.log(val)
      except:
        print(key, val)
    featureList.append( "%s=%s" % (key, val) )
  return str.join(' ', sorted(featureList))


def getTravatarFeatures(field):
  features = {}
  for strKeyVal in field.split():
    (key, val) = strKeyVal.split('=')
    val = record.getNumber(val)
#    if key in ['egfl', 'egfp', 'fgel', 'fgep']:
#      val = math.e ** val
#    if key[-1] not in ['p', 'w']:
#      val = math.e ** val
    if len(key) >= 4 :
      val = math.e ** val
    features[key] = val
  return features

