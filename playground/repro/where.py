# python3 where.py MODULE.wasm ADDRESS LENGTH DIR...: which files under DIR... hold any 24-byte piece of the active data
# segment at ADDRESS (as find.py reads segments), and at what offset, with 64 bytes around it.
import sys, pathlib
m = pathlib.Path(sys.argv[1]).read_bytes(); addr, ln = int(sys.argv[2]), int(sys.argv[3])
def leb(b, i):
    r = s = 0
    while True:
        x = b[i]; i += 1; r |= (x & 0x7f) << s; s += 7
        if x < 0x80: return r, i
i = 8
while i < len(m):
    sid = m[i]; size, j = leb(m, i + 1)
    if sid == 11:
        count, p = leb(m, j)
        for _ in range(count):
            _, p = leb(m, p); a, p = leb(m, p + 1); p += 1; l, p = leb(m, p)
            if a == addr: seg = m[p:p + l]
            p += l
    i = j + size
assert len(seg) == ln, len(seg)
probes = [seg[k:k + 24] for k in range(0, ln - 24, 48)]
print(f"segment: {seg.hex()}")
seen = 0
for d in sys.argv[4:]:
    for f in pathlib.Path(d).rglob("*") if pathlib.Path(d).exists() else []:
        if not f.is_file() or f.is_symlink() or f.stat().st_size > 400_000_000: continue
        try: data = f.read_bytes()
        except OSError: continue
        hits = [(k * 48, data.find(p)) for k, p in enumerate(probes) if p in data]
        if hits:
            seen += 1; at = hits[0][1]
            print(f"{f}: {len(hits)} of {len(probes)} pieces, first at {at}: {data[max(0, at - 64):at + 64].hex()}")
print(f"{seen} files hold a piece" if seen else "no file holds any piece: the linker made it")
