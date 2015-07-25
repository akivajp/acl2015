#!/usr/bin/env python
# -*- coding: utf-8 -*-

'''classes providing cache functions'''

import weakref
from collections import OrderedDict

DEFAULT_CACHE_SIZE = 100

'''dictionary class holding only least N records'''
class Cache(OrderedDict):
    def __init__(self, items = [], size = None):
        if not isinstance(size, int):
            if isinstance(items, Cache):
                size = items.__size
            else:
                size = DEFAULT_CACHE_SIZE
        self.__size = size
        OrderedDict.__init__(self, items)

    def __setitem__(self, key, value):
        if key in self:
            del self[key]
        OrderedDict.__setitem__(self, key, value)
        self.__resize()

    def __getsize(self):
        return self.__size

    def __resize(self, size = None):
        if isinstance(size, int):
            self.__size = size
        if self.__size > 0:
            while len(self) > self.__size:
                self.popitem(last = False)
        elif self.__size < 0:
            while len(self) > -(self.__size):
                self.popitem(last = True)

    def use(self, key, default = None):
        if key in self:
            value = OrderedDict.__getitem__(self, key)
            OrderedDict.__delitem__(self, key)
            OrderedDict.__setitem__(self, key, value)
            return value
        else:
            return default

    size = property(__getsize,__resize)


#'''class providing a framework to return the same ID for an object with the same value'''
#class InternCache(object):
#    def __init__(self, size = 0):
#        self.cache = Cache(size = size)
#
#    def clear(self):
#        self.cache.clear()
#
#    def intern(self, obj):
#        if not obj in self.cache:
#            self.cache[obj] = obj
#        return self.cache[obj]
#
#__internCache = InternCache()
#clear_intern_cache = __internCache.clear
#intern = __internCache.intern


class ObjectHold(object):
    def __init__(self, o):
        self.__dict__['o'] = o

    def __add__(self, rhs):
        return self.o + rhs

    def __cmp__(self, other):
        return cmp(self.o, other)

    def __getattr__(self, attr):
        return getattr(self.o, attr)

    def __getitem__(self, key):
        return self.o.__getitem__(key)

    def __getstate__(self):
        return self.__dict__

    def __hash__(self):
        return hash(self.o)

    def __radd__(self, lhs):
        return lhs + self.o

    def __repr__(self):
        c = self.__class__
        return "%s.%s(%r)" % (c.__module__,c.__name__,self.o)

    def __setattr__(self, key, val):
        raise AttributeError

    def __setstate__(self, state):
        return self.__dict__.update(state)

    def __str__(self):
        return str(self.o)


__internDict = weakref.WeakValueDictionary()
def intern(val):
    if val in __internDict:
        try:
            o = __internDict[val]
            return o
        except KeyError:
            pass
    o = ObjectHold(val)
    __internDict[val] = o
    return o

