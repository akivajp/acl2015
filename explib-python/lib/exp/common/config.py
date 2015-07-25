#!/usr/bin/env python
# -*- coding: utf-8 -*-

'''classes controlling config files'''

from collections import OrderedDict

import argparse
import files
import re

class Config(OrderedDict):
    def __init__(self, **vals):
        OrderedDict.__init__(self, **vals)

    def parse(self, filepath):
        fobj = files.open(filepath, 'r')
        field = ''
        for line in fobj:
            line = line.strip()
            m = re.match('\s*\[(.*)\]', line)
            if m:
                # setting for field name
                field = m.groups()[0]
            else:
                # parameter
                params = self.setdefault(field, [])
                params.append(line)

    def append(self, field, param):
        params = self.get(field, [])
        lastIndex = -1
        for i, p in enumerate(params):
            if p == '':
                # blank line
                pass
            elif re.match('\s*#', p):
                # comment
                pass
            else:
                lastIndex = i
        params.insert(lastIndex+1, param)

    def __str__(self):
        buf = ''
        for field, params in self.items():
            if field:
                buf += "[%s]\n" % (field)
            for param in params:
                buf += param + "\n"
        return buf

    def __repr__(self):
        cls = self.__class__
        r = super(cls,self).__repr__()
        return "%s.%s" % (cls.__module__,r)

