#!/usr/bin/env python
# -*- coding: utf-8 -*-

'''auxiliary container classes'''

from collections import Iterable

class Options(dict):
    def __add__(self, rhs):
        ops = Options(self)
        for key, val in rhs.items():
            if key not in ops:
                ops[key] = val
        return ops

    def __sub__(self, rhs):
        ops = Options(self)
        if isinstance(rhs, dict):
            for key, val in rhs.items():
                if key in ops:
                    if ops[key] == val:
                        del ops[key]
            return ops
        elif isinstance(rhs, Iterable):
            for key in rhs:
                if key in ops:
                    del ops[key]
            return ops
        else:
            assert False, "rhs should be iterable"

    def __or__(self, rhs):
        return self.__add__(rhs)

    def __radd__(self, lhs):
        return Options(lhs) + self

    def __ror__(self, lhs):
        return self.__radd__(lhs)

