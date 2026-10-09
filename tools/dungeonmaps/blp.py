"""Decode BLP2 textures (DXT1/3/5, palette, raw BGRA) and write PNGs, with nothing but the standard library.

Only the dungeon map tooling uses this: the client's map tiles are BLP files, and the review pages
need PNGs. The addon itself never reads images; it names file IDs.
"""
import struct
import zlib


def _rgb565(c):
    return ((c >> 11) & 31) * 255 // 31, ((c >> 5) & 63) * 255 // 63, (c & 31) * 255 // 31


def decode(path):
    """Return (width, height, RGBA bytearray) of the first mip level."""
    d = open(path, 'rb').read()
    if d[:4] != b'BLP2':
        raise ValueError(f'{path}: not a BLP2 file')
    _, comp, alpha_depth, alpha_type, _ = struct.unpack_from('<I4B', d, 4)
    w, h = struct.unpack_from('<II', d, 12)
    off = struct.unpack_from('<16I', d, 20)[0]
    pix = bytearray(w * h * 4)
    if comp == 2:
        dxt = 1 if alpha_depth == 0 else {1: 3, 7: 5}.get(alpha_type, 1)
        for by in range(0, h, 4):
            for bx in range(0, w, 4):
                alphas = None
                coff = off
                if dxt == 3:
                    av = int.from_bytes(d[off:off + 8], 'little')
                    alphas = [((av >> (4 * i)) & 15) * 17 for i in range(16)]
                    coff = off + 8
                elif dxt == 5:
                    a0, a1 = d[off], d[off + 1]
                    bits = int.from_bytes(d[off + 2:off + 8], 'little')
                    if a0 > a1:
                        tab = [a0, a1] + [((7 - i) * a0 + i * a1) // 7 for i in range(1, 7)]
                    else:
                        tab = [a0, a1] + [((5 - i) * a0 + i * a1) // 5 for i in range(1, 5)] + [0, 255]
                    alphas = [tab[(bits >> (3 * i)) & 7] for i in range(16)]
                    coff = off + 8
                c0, c1 = struct.unpack_from('<HH', d, coff)
                a, b = _rgb565(c0), _rgb565(c1)
                if c0 > c1 or dxt != 1:
                    cols = [a + (255,), b + (255,),
                            tuple((2 * a[i] + b[i]) // 3 for i in range(3)) + (255,),
                            tuple((a[i] + 2 * b[i]) // 3 for i in range(3)) + (255,)]
                else:
                    cols = [a + (255,), b + (255,), tuple((a[i] + b[i]) // 2 for i in range(3)) + (255,), (0, 0, 0, 0)]
                idx = struct.unpack_from('<I', d, coff + 4)[0]
                for i in range(16):
                    x, y = bx + (i & 3), by + (i >> 2)
                    if x < w and y < h:
                        c = cols[(idx >> (2 * i)) & 3]
                        p = (y * w + x) * 4
                        pix[p:p + 4] = bytes((c[0], c[1], c[2], alphas[i] if alphas else c[3]))
                off += 8 if dxt == 1 else 16
    elif comp == 3:
        for i in range(w * h):
            b, g, r, a = d[off + 4 * i:off + 4 * i + 4]
            pix[4 * i:4 * i + 4] = bytes((r, g, b, a))
    elif comp == 1:
        pal = [struct.unpack_from('<4B', d, 148 + 4 * i) for i in range(256)]
        for i in range(w * h):
            b, g, r, _ = pal[d[off + i]]
            pix[4 * i:4 * i + 4] = bytes((r, g, b, 255))
        if alpha_depth == 8:
            for i in range(w * h):
                pix[4 * i + 3] = d[off + w * h + i]
    else:
        raise ValueError(f'{path}: compression {comp} not supported')
    return w, h, pix


def write_png(path, w, h, pix):
    raw = b''.join(b'\x00' + bytes(pix[y * w * 4:(y + 1) * w * 4]) for y in range(h))

    def chunk(tag, body):
        return struct.pack('>I', len(body)) + tag + body + struct.pack('>I', zlib.crc32(tag + body) & 0xffffffff)

    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b'IDAT', zlib.compress(raw, 6)))
        f.write(chunk(b'IEND', b''))
