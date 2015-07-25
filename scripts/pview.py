#!/usr/bin/env python
# -*- coding: utf-8 -*-

import sys

WIDTH = 50

def usage():
  print("usage: %s [-s=separator] [-w=width] file1 [-w=width] file2 ..." % sys.argv[0])
  print("")
  print("options:")
  print("  -s=sequence : joining separator (default -s=\"|||\")")
  print("  -w=width    : max length of each file line (default -w=%d)" % WIDTH)
  sys.exit(1)


class Item:
  def __init__(self, filename, width, sep):
    self.fileobj = open(filename, 'r')
    self.width =  width
    self.sep   =  sep
    self.eof   = False

  def fetch(self):
    line = self.fileobj.readline()
    if line == "":
      self.eof = True
    line = line.strip()
    line = line[:self.width]
    line = line.ljust( self.width )
    self.line = line

class Config:
  def __init__(self, args):
    self.parse(args)
    self.count = 1

  def parse(self, args):
    s = "|||"
    w = WIDTH
    items = []
    for arg in args[1:]:
      if arg.find("-") == 0:
        fields = arg.split('=')
        if arg.find("-s") == 0:
          s = fields[1]
        if arg.find("-w") == 0:
          w = int(fields[1])
      else:
        items.append( Item(arg, w, s) )
    self.items = items

  def fetch(self):
    for item in self.items:
      item.fetch()

  def isDone(self):
    for item in self.items:
      if item.eof != True:
        return False
    return True

  def pview(self):
    if len(self.items) == 0:
      usage()
    while True:
      self.fetch()
      if self.isDone():
        return
      sys.stdout.write( "%3d: " % self.count )
      #sys.stdout.write( "%d: " % self.count )
      self.count += 1
      for i, item in enumerate(self.items):
        sys.stdout.write( item.line )
        if i + 1 < len(self.items):
          sys.stdout.write( " %s " % item.sep )
        else:
          sys.stdout.write("\n")

def pview(args):
  conf = Config(args)
  conf.pview()

if __name__ == '__main__':
  pview(sys.argv)

