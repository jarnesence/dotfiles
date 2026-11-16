#!/usr/bin/env python3
"""Tiny stub-resolver used by dns.sh — no dig/drill on this box.

  dnsq.py query  SERVER NAME [TYPE]   one lookup, prints rcode/rtt/answers
  dnsq.py bench  NAME SERVER...       latency per server, sorted, best first
  dnsq.py who                         which resolver IP the world actually sees
"""
import socket, struct, sys, time

TYPES = {'A': 1, 'NS': 2, 'CNAME': 5, 'TXT': 16, 'AAAA': 28, 'HTTPS': 65}
RCODES = {0: 'NOERROR', 1: 'FORMERR', 2: 'SERVFAIL', 3: 'NXDOMAIN',
          4: 'NOTIMP', 5: 'REFUSED'}


def build(name, qtype, tid):
    pkt = struct.pack('>HHHHHH', tid, 0x0100, 1, 0, 0, 0)
    for label in name.rstrip('.').split('.'):
        pkt += bytes([len(label)]) + label.encode()
    return pkt + b'\x00' + struct.pack('>HH', qtype, 1)


def read_name(buf, off):
    """Returns (name, offset_after). Follows compression pointers."""
    parts, jumped, hops = [], False, 0
    end = off
    while True:
        if off >= len(buf) or hops > 64:
            break
        ln = buf[off]
        if ln & 0xC0 == 0xC0:                      # pointer
            ptr = struct.unpack('>H', buf[off:off + 2])[0] & 0x3FFF
            if not jumped:
                end = off + 2
            off, jumped, hops = ptr, True, hops + 1
            continue
        off += 1
        if ln == 0:
            if not jumped:
                end = off
            break
        parts.append(buf[off:off + ln].decode('utf-8', 'replace'))
        off += ln
    return '.'.join(parts), end


def parse(buf):
    tid, flags, qd, an = struct.unpack('>HHHH', buf[:8])
    off = 12
    for _ in range(qd):                            # skip question section
        _, off = read_name(buf, off)
        off += 4
    out = []
    for _ in range(an):
        _, off = read_name(buf, off)
        rtype, _cls, _ttl, rdlen = struct.unpack('>HHIH', buf[off:off + 10])
        off += 10
        rd = buf[off:off + rdlen]
        if rtype == 1 and rdlen == 4:
            out.append(socket.inet_ntop(socket.AF_INET, rd))
        elif rtype == 28 and rdlen == 16:
            out.append(socket.inet_ntop(socket.AF_INET6, rd))
        elif rtype == 16:
            txt, i = [], 0
            while i < rdlen:
                n = rd[i]
                txt.append(rd[i + 1:i + 1 + n].decode('utf-8', 'replace'))
                i += 1 + n
            out.append('"%s"' % ''.join(txt))
        elif rtype in (2, 5):
            out.append(read_name(buf, off)[0])
        off += rdlen
    return flags & 0xF, out


def ask(server, name, qtype='A', timeout=5.0):
    """-> (rcode, answers, milliseconds). Raises on transport failure."""
    fam = socket.AF_INET6 if ':' in server else socket.AF_INET
    s = socket.socket(fam, socket.SOCK_DGRAM)
    s.settimeout(timeout)
    tid = int(time.time() * 1000) & 0xFFFF
    try:
        t0 = time.monotonic()
        s.sendto(build(name, TYPES.get(qtype.upper(), 1), tid), (server, 53))
        while True:                                # ignore stale/foreign replies
            data, _ = s.recvfrom(4096)
            if len(data) >= 2 and struct.unpack('>H', data[:2])[0] == tid:
                break
        ms = (time.monotonic() - t0) * 1000
        rcode, answers = parse(data)
        return rcode, answers, ms
    finally:
        s.close()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cmd = sys.argv[1]

    if cmd == 'query':
        server, name = sys.argv[2], sys.argv[3]
        qtype = sys.argv[4] if len(sys.argv) > 4 else 'A'
        try:
            rcode, answers, ms = ask(server, name, qtype)
        except Exception as e:
            print('  \x1b[31mFAIL\x1b[0m  %s  (%s)' % (server, e))
            return 1
        tag = RCODES.get(rcode, 'RCODE%d' % rcode)
        color = '32' if rcode == 0 and answers else '33'
        print('  \x1b[%sm%s\x1b[0m  %s  %.0f ms  via %s' % (color, tag, name, ms, server))
        for a in answers:
            print('      %s' % a)
        if not answers and rcode == 0:
            print('      (no records of type %s)' % qtype.upper())
        return 0 if rcode == 0 else 1

    if cmd == 'bench':
        name, servers = sys.argv[2], sys.argv[3:]
        rows = []
        for srv in servers:
            label, _, addr = srv.partition('=')     # "Cloudflare=1.1.1.1"
            addr = addr or label
            try:
                rcode, _, ms = ask(addr, name, timeout=3.0)
                rows.append((ms if rcode == 0 else 9e9, label, addr,
                             '%.0f ms' % ms if rcode == 0 else RCODES.get(rcode, '?')))
            except Exception:
                rows.append((9e9, label, addr, 'timeout'))
        rows.sort()
        print('  %-26s %-30s %s' % ('resolver', 'address', 'latency'))
        print('  %s' % ('─' * 68))
        for i, (_, label, addr, res) in enumerate(rows):
            mark = '\x1b[32m★\x1b[0m' if i == 0 and 'ms' in res else ' '
            print('%s %-26s %-30s %s' % (mark, label[:26], addr[:30], res))
        return 0

    if cmd == 'who':
        # Google's resolver-identity probe: answers with the IP that asked.
        try:
            _, answers, _ = ask('127.0.0.53', 'o-o.myaddr.l.google.com', 'TXT', 6.0)
            print('\n'.join('  egress resolver: %s' % a for a in answers) or '  (no answer)')
        except Exception as e:
            print('  probe failed: %s' % e)
            return 1
        return 0

    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main())
