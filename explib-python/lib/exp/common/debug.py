#!/usr/bin/env python
# -*- coding: utf-8 -*-

'''auxiliary functions for debug printing'''

import codecs
import inspect
import sys

_debugging = True

def _show_caller():
    s = inspect.stack()[2]
    frame    = s[0]
    filename = s[1]
    line     = s[2]
    name     = s[3]
    code     = s[4]
    if code:
        sys.stdout.write("[%s:%s] %s: " % (filename, line, code[0].strip() ))
    else:
        sys.stdout.write("[%s:%s] : " % (filename, line) )


def _str(arg):
    if sys.version_info.major == 3:
        return str(arg)
    else:
        if type(arg) == str:
            return arg.decode('utf-8')
        else:
            return unicode(arg)


stdout = codecs.getwriter('utf-8')(sys.stdout)
def log(*args, **keys):
    '''print the value with the line calling this function'''
    if _debugging:
        if not 'sep' in keys:
            keys['sep'] = ' '
        if not 'end' in keys:
            keys['end'] = "\n"
        _show_caller()
        stdout.write( keys['sep'].join( map(_str, args) ) )
        stdout.write( keys['end'] )
        stdout.flush()


def enable():
    '''enable debug mode'''
    global _debugging
    _debugging = True


def disable():
    '''disable debug mode'''
    global _debugging
    _debugging = False

