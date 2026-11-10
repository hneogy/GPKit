# python3 find.py A.wasm B.wasm BUILD-DIR: where two modules part, by wasm section and data segment, and which object
# files under BUILD-DIR hold the parted bytes of A (so which symbol carries them: wasm-objdump -x on that file).
import sys, pathlib
a, b = (pathlib.Path(p).read_bytes() for p in sys.argv[1:3])
def leb(buf, i):
    r = s = 0
    while True:
        x = buf[i]; i += 1; r |= (x & 0x7f) << s; s += 7
        if x < 0x80: return r, i
if len(a) != len(b): print(f"sizes differ: {len(a)} and {len(b)}")
n = min(len(a), len(b))
diffs = [i for i in range(n) if a[i] != b[i]]
print(f"{len(diffs)} bytes differ" + (f", from {diffs[0]} to {diffs[-1]}" if diffs else ""))
if not diffs: sys.exit(0)
i, sections = 8, []
while i < len(a):
    sid = a[i]; size, j = leb(a, i + 1); sections.append((sid, i, j + size)); i = j + size
for sid, s, e in sections:
    k = [x for x in diffs if s <= x < e]
    if k: print(f"section {sid} [{s}, {e}): {len(k)} bytes differ")
    if k and sid == 11:  # data: each segment's memory offset and length
        count, p = leb(a, s + 1); _, p = leb(a, s + 1)
        count, p = leb(a, p)
        for _ in range(count):
            flag, p = leb(a, p)
            assert flag == 0 and a[p] == 0x41, "an active segment with an i32.const offset"
            addr, p = leb(a, p + 1); assert a[p] == 0x0b; p += 1
            ln, p = leb(a, p)
            kk = [x for x in k if p <= x < p + ln]
            if kk:
                print(f"  segment at memory {addr} (0x{addr:x}), {ln} bytes, {len(kk)} differ, file offset {p}")
                seg = a[p:p + ln]
                for probe_at in (0, ln // 2, max(0, ln - 24)):
                    probe = seg[probe_at:probe_at + 24]
                    hits = [f for f in pathlib.Path(sys.argv[3]).rglob("*.o") if probe in f.read_bytes()]
                    print(f"    bytes {probe_at}..{probe_at + 24} ({probe.hex()}) found in: {[str(h) for h in hits] or 'no object file'}")
                print(f"    A: {seg[:64].hex()}")
                print(f"    B: {b[p:p + 64].hex()}")
            p += ln
