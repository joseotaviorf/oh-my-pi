#!/usr/bin/env python

from __future__ import with_statement, print_function

import os
import re
import shutil
import subprocess
import sys
import tempfile

ignore_codes = ['E501']

def system(*args, **kwargs):
    kwargs.setdefault('stdout', subprocess.PIPE)
    proc = subprocess.Popen(args, **kwargs)
    out, err = proc.communicate()
    return out


def main():
    modified = re.compile('^[AM]+\s+(?P<name>.*\.py$)', re.MULTILINE)
    files = system('git', 'status', '--porcelain').decode("utf-8")
    files = modified.findall(files)

    tempdir = tempfile.mkdtemp()
    for name in files:
        filename = os.path.join(tempdir, name)
        filepath = os.path.dirname(filename)

        if not os.path.exists(filepath):
            os.makedirs(filepath)
        with open(filename, 'w') as f:
            system('git', 'show', ':' + name, stdout=f)

    args = ['pycodestyle']
    if ignore_codes:
        args.extend(('--ignore', ','.join(ignore_codes)))
    args.append('.')

    output = system(*args, cwd=tempdir)
    shutil.rmtree(tempdir)
    if output:
        print(u'PEP8 style violations have been detected!\n')
        print(output.decode("utf-8"), )
        sys.exit(1)


if __name__ == '__main__':
    main()

