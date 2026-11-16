#!/usr/bin/env python3
"""Comment-preserving key editor for dnscrypt-proxy.toml.

The upstream toml carries ~900 lines of documentation; a real TOML round-trip
would throw all of it away, so this edits the one matching line in place.

  dnstoml.py get KEY [--section S]
  dnstoml.py set KEY 'VALUE' [--section S]     VALUE is raw TOML ("true", "['a']")

Section defaults to the top-level block (everything before the first [table]).
A commented-out key is uncommented in place; a missing key is appended to its
section. Exit 0 on success.
"""
import re
import sys

PATH = '/etc/dnscrypt-proxy/dnscrypt-proxy.toml'


def section_bounds(lines, section):
    """-> (start, end) line indices for the requested table."""
    if section is None:
        for i, ln in enumerate(lines):
            if re.match(r'^\s*\[', ln):
                return 0, i
        return 0, len(lines)
    want = '[%s]' % section
    start = None
    for i, ln in enumerate(lines):
        if ln.strip() == want:
            start = i + 1
            break
    if start is None:
        return None, None
    for j in range(start, len(lines)):
        if re.match(r'^\s*\[', lines[j]):
            return start, j
    return start, len(lines)


def find_key(lines, key, lo, hi):
    """-> (index, is_commented). Live line wins over a commented example."""
    live = re.compile(r'^\s*%s\s*=' % re.escape(key))
    dead = re.compile(r'^\s*#\s*%s\s*=' % re.escape(key))
    commented = None
    for i in range(lo, hi):
        if live.match(lines[i]):
            return i, False
        if commented is None and dead.match(lines[i]):
            commented = i
    return (commented, True) if commented is not None else (None, None)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    cmd, key = sys.argv[1], sys.argv[2]
    args = sys.argv[3:]
    section = None
    if '--section' in args:
        k = args.index('--section')
        section = args[k + 1]
        args = args[:k] + args[k + 2:]

    with open(PATH, encoding='utf-8') as fh:
        lines = fh.read().splitlines(keepends=True)

    lo, hi = section_bounds(lines, section)
    if lo is None:
        print('no such section: [%s]' % section, file=sys.stderr)
        return 1
    idx, _ = find_key(lines, key, lo, hi)

    if cmd == 'get':
        if idx is None or lines[idx].lstrip().startswith('#'):
            return 1                                   # unset / commented out
        print(lines[idx].split('=', 1)[1].strip())
        return 0

    if cmd == 'set':
        if not args:
            print('set needs a value', file=sys.stderr)
            return 2
        new = '%s = %s\n' % (key, args[0])
        if idx is None:
            lines.insert(hi, new)                      # append into section
        else:
            lines[idx] = new
        with open(PATH, 'w', encoding='utf-8') as fh:
            fh.writelines(lines)
        return 0

    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main())
