#!/usr/bin/env python
# -*- coding: utf-8 -*-

'''2つのフレーズテーブルをピボット側で周辺化しし、新しく1つのフレーズテーブルを合成する．'''

import argparse
import codecs
import math
import multiprocessing
import sys
import time

# my exp libs
from exp.common import cache, debug, files, progress
from exp.phrasetable import findutil

#THRESHOLD = 1e-2
THRESHOLD = 0 # 打ち切り無し
NBEST = 30

class WorkSet:
  '''マルチプロセス処理に必要な情報をまとめたもの'''
  def __init__(self, savefile):
    f_out = files.open(savefile, 'wb')
    self.fileobj = codecs.getwriter('utf-8')(f_out)
    self.pivot_count = progress.Counter(scaleup = 1000)
    self.record_queue = multiprocessing.Queue()
    self.pivot_queue  = multiprocessing.Queue()
    self.marginalizer = multiprocessing.Process( target = marginalize, args=(self,) )
    self.recorder = multiprocessing.Process( target = write_records, args = (self,) )

  def __del__(self):
    self.close()

  def close(self):
    if self.marginalizer.pid:
      if self.marginalizer.exitcode == None:
        self.marginalizer.terminate()
      self.marginalizer.join()
    if self.recorder.pid:
      if self.recorder.exitcode == None:
        self.recorder.terminate()
      self.recorder.join()
    self.record_queue.close()
    self.pivot_queue.close()
    self.fileobj.close()

  def join(self):
    self.marginalizer.join()
    self.recorder.join()

  def start(self):
    self.marginalizer.start()
    self.recorder.start()

  def terminate(self):
    self.marginalizer.terminate()
    self.recorder.terminate()


def add_scores(record, scores1, scores2):
  '''スコアを掛けあわせて累積値に加算する'''
  scores = record[0]
  for i in range(0, len(scores)):
    scores[i] += scores1[i] * scores2[i]

def update_counts(record, counts1, counts2):
  '''ルールの出現頻度を更新'''
  counts = record[2]
  counts[2] += math.sqrt(counts1[2] * counts2[2])
  #counts[2] += min(counts1[2], counts2[2])

def infer_counts(counts, scores):
  '''スコアと、推定された共起回数からそれぞれの頻度を算出する'''
  counts[0] = counts[2] / scores[0]
  counts[1] = counts[2] / scores[2]

def merge_alignment(record, align1, align2):
  '''アラインメントのマージを試みる'''
  align = record[1]
  a1 = {}
  for pair in align1:
    (left, right) = pair.split('-')
    if not left in a1:
      a1[left] = []
    a1[left].append(right)
  a2 = {}
  for pair in align2:
    (left, right) = pair.split('-')
    if not left in a2:
      a2[left] = []
    a2[left].append(right)
  for left in a1.keys():
    for middle in a1[left]:
      if middle in a2:
        for right in a2[middle]:
          pair = '%(left)s-%(right)s' % locals()
          align[pair] = True

def marginalize(workset):
  '''条件付き確率の周辺化を行うワーカー関数

  ピボット対象のレコードの配列を record_queue で受け取り、処理したデータを pivot_queue で渡す'''
  row_count = 0
  while True:
    # 処理すべきレコード配列を発見
    rows = workset.record_queue.get()
    if rows == None:
      # None を受け取ったらプロセス終了
      break
    #debug.log(len(rows))

    records = {}
    source = ''
    for row in rows:
      row_count += 1
      #print(row)
      source = row[0]
      pivot_phrase = row[1] # 参考までに取得しているが使わない
      target = row[2]
      scores1 = [float(score) for score in row[3].split(' ')]
      scores2 = [float(score) for score in row[4].split(' ')]
      align1 = row[5].split(' ')
      align2 = row[6].split(' ')
      counts1 = [float(count) for count in row[7].split(' ')]
      counts2 = [float(count) for count in row[8].split(' ')]
      pair = source + ' ||| ' + target + ' ||| '
      if not pair in records:
        # 対象言語の訳出のレコードがまだ無いので作る
        records[pair] = [ [0, 0, 0, 0], {}, [0, 0, 0] ]
      record = records[pair]
      # 訳出のスコア(条件付き確率)を掛けあわせて加算する
      add_scores(record, scores1, scores2)
      # フレーズ対応の出現頻度を推定（共起回数のみ推定）
      update_counts(record, counts1, counts2)
      # アラインメントのマージ
      merge_alignment(record, align1, align2)
    if THRESHOLD > 0:
      # 非常に小さな翻訳確率のフレーズは無視する
      ignoring = []
      for pair, rec in records.items():
        #infer_counts(rec[2], rec[0])
        if rec[0][0] < THRESHOLD and rec[0][2] < THRESHOLD:
          #print("\nignoring '%(source)s' -> '%(target)s' %(rec)s" % locals())
          ignoring.append(pair)
        #elif rec[0][1] < IGNORE ** 2 and rec[0][3] < IGNORE ** 2:
        #  ignoring.append( (source, target) )
        #elif rec[0][0] < IGNORE ** 2 or rec[0][2] < IGNORE ** 2:
        #  ignoring.append( (source, target) )
        #elif (rec[2][0] > 10 or rec[2][1] > 10) and rec[2][2] < 2:
        #  ignoring.append( (source, target) )
      for pair in ignoring:
        del records[pair]
    if NBEST > 0:
      for pair in records.keys():
        rec = records[pair]
#        rec.append( rec[0][0] * rec[0][1] * rec[0][2] * rec[0][3] )
        rec.append( rec[0][2] ) # by P(e|f)
#        rec.append( rec[0][2] * rec[0][3] )
#        rec.append( rec[0][0] * rec[0][1] )
        #debug.log( rec[3] )
      best_records = {}
      for pair in sorted(records.keys(), reverse=True, key=lambda pair: records[pair][3])[:NBEST]:
        rec = records[pair]
        best_records[pair] = records[pair]
        #debug.log( rec[3] )
      records = best_records
    # 周辺化したレコードをキューに追加して、別プロセスに書き込んでもらう
    if records:
      #debug.log( len(records) )
      workset.pivot_count.add( len(records) )
      for pair in sorted(records.keys()):
        rec = records[pair]
        infer_counts(rec[2], rec[0])
        #workset.pivot_queue.put([ pair[0], pair[1], rec[0], rec[1], rec[2] ])
        workset.pivot_queue.put([ pair, rec[0], rec[1], rec[2] ])
  # while ループを抜けた
  # write_records も終わらせる
  workset.pivot_queue.put(None)

def write_records(workset):
  '''キューに溜まったピボット済みのレコードをファイルに書き出す'''
  while True:
    rec = workset.pivot_queue.get()
    if rec == None:
      # Mone を受け取ったらループ終了
      break
    #source = rec[0]
    #target = rec[1]
    pair = rec[0]
    scores = str.join(' ', map(str, rec[1]))
    align  = str.join(' ', sorted(rec[2].keys()) )
    counts = str.join(' ', map(str, rec[3]) )
    #buf  = source + ' ||| '
    #buf += target + ' ||| '
    buf  = pair # source ||| target ||| という形式になっている
    buf += scores + ' ||| '
    buf += align  + ' ||| '
    buf += counts + ' |||'
    buf += "\n"
    #workset.fileobj.write(buf)
    workset.fileobj.write( buf.decode('utf-8') )
  workset.fileobj.close()

class PivotFinder:
  def __init__(self, table1, table2, src_index, trg_index):
    self.fobj_src = files.open(table1, 'r')
    self.fobj_trg = open(table2, 'r')
    self.src_indices = findutil.load_indices(src_index)
    self.trg_indices = findutil.load_indices(trg_index)
    self.source_count = progress.Counter(scaleup = 1000)
    self.rows = []
    self.rows_cache = cache.Cache(1000)
    #self.rows_cache = cache.Cache(100)

  def getRow(self):
    if self.rows == None:
      return None
    while len(self.rows) == 0:
      line = self.fobj_src.readline()
      self.source_count.add()
      if not line:
        self.rows = None
        return None
      rec = line.strip()
      self.makePivot(rec)
    return self.rows.pop(0)

  def makePivot(self, rec):
    fields = rec.split('|||')
    #print("REC: %s" % rec)
    pivot_phrase = fields[1].strip()
    if pivot_phrase in self.rows_cache:
      #print("CACHE HIT: %s" % pivot_phrase)
      trg_records = self.rows_cache.use(pivot_phrase)
      #trg_records = self.rows_cache[pivot_phrase]
      #self.rows_cache.use(pivot_phrase)
    else:
      trg_records = findutil.indexed_binsearch(self.fobj_trg, self.trg_indices, pivot_phrase)
      #print("LEN TRG: %s" % len(trg_records))
      #print("CACHING: %s" % pivot_phrase)
      self.rows_cache[pivot_phrase] = trg_records
    for trg_rec in trg_records:
      trg_fields = trg_rec.split('|||')
      #print("TRG: %s" % trg_rec)
      row = []
      row.append( fields[0].strip() )
      row.append( pivot_phrase )
      row.append( trg_fields[1].strip() )
      row.append( fields[2].strip() )
      row.append( trg_fields[2].strip() )
      row.append( fields[3].strip() )
      row.append( trg_fields[3].strip() )
      row.append( fields[4].strip() )
      row.append( trg_fields[4].strip() )
      self.rows.append( row )

def pivot(workset, table1, table2, src_index, trg_index):
  # 周辺化を行う対象フレーズ
  # curr_phrase -> pivot_phrase -> target の形の訳出を探す
  try:
    workset.start()
    finder = PivotFinder(table1, table2, src_index, trg_index)
    curr_phrase = ''
    rows = []
    row_count = 0
    while True:
      if workset.record_queue.qsize() > 2000:
        time.sleep(1)
      row = finder.getRow()
      if not row:
        break
      row_count += 1
      source = row[0]
      #print("ROW: %s" % row)
      #print("LEN ROWS: %d" % len(rows))
      if curr_phrase != source:
        # 新しい原言語フレーズが出てきたので、ここまでのデータを開いてるプロセスに処理してもらう
        workset.record_queue.put(rows)
        rows = []
        curr_phrase = source
        #debug.log(workset.record_queue.qsize())
        #debug.log(workset.pivot_queue.qsize())
      rows.append(row)
      if finder.source_count.should_print():
        finder.source_count.update()
        nSource = finder.source_count.count
        ratio = 100.0 * finder.source_count.count / len(finder.src_indices)
        progress.log("source: %d (%3.2f%%), processed: %d, last phrase: %s" %
                     (nSource, ratio, row_count, source) )
    # while ループを抜けた
    # 最後のデータ処理
    workset.record_queue.put(rows)
    workset.record_queue.put(None)
    # 書き出しプロセスの正常終了待ち
    workset.join()
    progress.log("source: %d (100%%), processed: %d, pivot %d\n" %
                 (finder.source_count.count, row_count, workset.pivot_count.count) )
    # ワークセットを片付ける
    workset.close()
  except KeyboardInterrupt:
    # 例外発生、全てのワーカープロセスを停止させる
    print('')
    print('Caught KeyboardInterrupt, terminating all the worker processes')
    workset.close()
    sys.exit(1)

if __name__ == '__main__':
  parser = argparse.ArgumentParser(description = 'load 2 phrase tables and pivot into one moses phrase table')
  parser.add_argument('table1', help = 'phrase table 1')
  parser.add_argument('table2', help = 'phrase table 2')
  parser.add_argument('savefile', help = 'path for saving moses phrase table file')
  parser.add_argument('--threshold', help = 'threshold for ignoring the phrase translation probability (real number)', type=float, default=THRESHOLD)
  parser.add_argument('--nbest', help = 'best n scores for phrase pair filtering (default = 20)', type=int, default=NBEST)
  args = vars(parser.parse_args())

  THRESHOLD = args['threshold']
  del args['threshold']
  NBEST = args['nbest']
  del args['nbest']
  workset = WorkSet(args['savefile'])
  del args['savefile']

  src_index = args['table1'] + '.index'
  print("making index: %(src_index)s" % locals())
  findutil.save_indices(args['table1'], src_index)
  args['src_index'] = src_index

  trg_index = args['table2'] + '.index'
  print("making index: %(trg_index)s" % locals())
  findutil.save_indices(args['table2'], trg_index)
  args['trg_index'] = trg_index

  pivot(workset = workset, **args)

