"""Generate StaticData/DungeonMaps.lua: each dungeon's floors, and the sections the fog lifts by.

Usage: python3 tools/dungeonmaps/build.py [instanceID ...]

What it does (docs/dungeon-maps.md):
1. A floor is a retail dungeon map (12 tiles of 256 px, shown at 1002 x 668) or, for Forever's new
   instances, a crop of the instance's minimap tiles. The script puts the floor together from
   Forever's own files to look at it; the addon only gets the file IDs.
2. Anchors: the entrance (where AzerothCore's teleport puts the player) and every boss (AzerothCore's
   spawn, else retail's encounter journal, else a hand-placed spot from dungeons.py), turned into
   positions on the floor through retail's UiMapAssignment.
3. Sections: the floor's walkable parchment is split on a grid of 64 columns by walking distance to
   the anchors, then grown over the drawing around it (rock, walls). Cells that are plain parchment
   get no section: they are never fogged.
4. The Lua file, and a review page in .cache/review/ that shows every floor with its sections.
"""
import html
import os
import struct
import sys
from collections import deque

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blp  # noqa: E402
import sources as S  # noqa: E402
from dungeons import DUNGEONS  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_LUA = os.path.join(HERE, '..', '..', 'StaticData', 'DungeonMaps.lua')
REVIEW = os.path.join(S.CACHE, 'review')

COLS = 64
ART_W, ART_H = 1002, 668
TILE_YARDS = 1600 / 3
MINIMAP_PX = 512
# light/dark: how much lighter (floor) or darker (rock, walls) than the map's own parchment, which is
# the median lightness of the picture. floor/drawing: the share of a cell that must be floor or drawing.
# spread: cells the sections grow over the drawing; margin: cells at the edge (the frame) never fogged.
DEFAULTS = {'light': 20, 'blur': 2, 'floor': 0.15, 'dark': 22, 'drawing': 0.3, 'spread': 3, 'margin': 2}
PALETTE = [(230, 60, 60), (60, 160, 230), (80, 200, 90), (240, 200, 40), (200, 90, 220), (240, 140, 40),
           (40, 210, 200), (250, 120, 170), (150, 150, 255), (180, 230, 80), (255, 255, 255), (160, 110, 60)]


def norm(name):
    return ' '.join((name or '').strip().strip('"').lower().split())


# --- Inputs ---------------------------------------------------------------------------------------

class Data:
    def __init__(self):
        self.maps = {r['ID']: r for r in S.table('Map', S.FOREVER)}
        self.map_names_de = {r['ID']: r['MapName_lang'] for r in S.table('Map', S.FOREVER, 'deDE')}
        self.encounters = S.table('DungeonEncounter', S.FOREVER)
        self.encounter_names_de = {r['ID']: r['Name_lang'] for r in S.table('DungeonEncounter', S.FOREVER, 'deDE')}
        self.art_of = {}
        for r in S.table('UiMapXMapArt', S.RETAIL):
            if r['PhaseID'] == '0':
                self.art_of.setdefault(r['UiMapID'], r['UiMapArtID'])
        self.tiles = {}
        for r in S.table('UiMapArtTile', S.RETAIL):
            if r['LayerIndex'] == '0':
                self.tiles.setdefault(r['UiMapArtID'], {})[(int(r['RowIndex']), int(r['ColIndex']))] = int(r['FileDataID'])
        self.assign = {}
        for r in S.table('UiMapAssignment', S.RETAIL):
            self.assign.setdefault(r['UiMapID'], []).append(r)
        self.journal = {}
        for r in S.table('JournalEncounter', S.RETAIL):
            self.journal.setdefault(norm(r['Name_lang']), []).append(r)
        self.floor_names = {}
        for locale in ('enUS', 'deDE'):
            for r in S.table('UiMapGroupMember', S.RETAIL, None if locale == 'enUS' else locale):
                self.floor_names.setdefault(r['UiMapID'], {})[locale] = r['Name_lang']
        self.npcs = {}
        for r in S.ac_rows('creature_template'):
            self.npcs.setdefault(norm(r['name']), []).append(int(r['entry']))
        self.spawns = {}
        for r in S.ac_rows('creature'):
            pos = (float(r['position_x']), float(r['position_y']), float(r['position_z']))
            for key in ('id1', 'id2', 'id3'):
                if r.get(key) and r[key] != '0':
                    self.spawns.setdefault((int(r[key]), int(r['map'])), []).append(pos)
        self.entrances = {}
        for r in S.ac_rows('areatrigger_teleport'):
            pos = (float(r['target_position_x']), float(r['target_position_y']), float(r['target_position_z']))
            self.entrances.setdefault(int(r['target_map']), []).append(pos)


# --- Floors ---------------------------------------------------------------------------------------

class Floor:
    """One map page: its picture (for the script), its world -> map transform and its Lua fields."""

    def __init__(self, index, spec):
        self.index, self.spec = index, spec
        self.tune = dict(DEFAULTS, **spec.get('tune', {}))
        self.name = None

    def contains(self, u, v):
        return 0 <= u <= 1 and 0 <= v <= 1


class ArtFloor(Floor):
    def __init__(self, index, spec, data, instance):
        super().__init__(index, spec)
        self.uimap = str(spec['uimap'])
        art = data.art_of[self.uimap]
        self.tile_ids = data.tiles[art]
        self.rows_assign = [a for a in data.assign.get(self.uimap, []) if a['MapID'] == str(instance)]
        self.name = data.floor_names.get(self.uimap)
        self.w, self.h = ART_W, ART_H
        self.pix = bytearray(ART_W * ART_H * 4)
        for (r, c), fid in self.tile_ids.items():
            w, h, p = blp.decode(S.client_file(fid))
            for y in range(h):
                Y, x0 = r * 256 + y, c * 256
                n = min(w, ART_W - x0)
                if Y < ART_H and n > 0:
                    self.pix[(Y * ART_W + x0) * 4:(Y * ART_W + x0 + n) * 4] = p[y * w * 4:(y * w + n) * 4]

    def to_uv(self, x, y, z):
        for a in self.rows_assign:
            x0, y0, z0, x1, y1, z1 = (float(a[f'Region_{i}']) for i in range(6))
            if x0 <= x <= x1 and y0 <= y <= y1 and z0 - 2 <= z <= z1 + 2:
                u0, v0 = float(a['UiMin_0']), float(a['UiMin_1'])
                u1, v1 = float(a['UiMax_0']), float(a['UiMax_1'])
                u = u0 + (u1 - u0) * (y1 - y) / (y1 - y0)
                v = v0 + (v1 - v0) * (x1 - x) / (x1 - x0)
                if self.contains(u, v):
                    return u, v
        return None

    def lua(self):
        ids = [self.tile_ids[(r, c)] for r in range(3) for c in range(4)]
        return {'art': ids}


class MinimapFloor(Floor):
    """A crop of an instance's minimap tiles: `minimap = (tx0, ty0, tx1, ty1)` in ADT tile units."""

    def __init__(self, index, spec, data, instance):
        super().__init__(index, spec)
        wdt = open(S.client_file(int(data.maps[str(instance)]['WdtFileDataID'])), 'rb').read()
        self.all_tiles = {}
        off = 0
        while off + 8 <= len(wdt):
            magic, size = wdt[off:off + 4][::-1], struct.unpack_from('<I', wdt, off + 4)[0]
            if magic == b'MAID':
                for i in range(4096):
                    e = struct.unpack_from('<8I', wdt, off + 8 + 32 * i)
                    if e[7]:
                        self.all_tiles[(i // 64, i % 64)] = e[7]
            off += 8 + size
        self.crop = tuple(spec['minimap'])
        tx0, ty0, tx1, ty1 = self.crop
        scale = spec.get('px', 384)  # review pixels per tile
        self.w, self.h = round((tx1 - tx0) * scale), round((ty1 - ty0) * scale)
        self.pix = bytearray(self.w * self.h * 4)
        decoded = {}
        for py in range(self.h):
            ty = ty0 + py / scale
            for px in range(self.w):
                tx = tx0 + px / scale
                key = (int(ty), int(tx))
                fid = self.all_tiles.get(key)
                if fid is None:
                    continue
                if key not in decoded:
                    decoded[key] = blp.decode(S.client_file(fid))
                w, h, p = decoded[key]
                sx, sy = int((tx - int(tx)) * w), int((ty - int(ty)) * h)
                si, di = (sy * w + sx) * 4, (py * self.w + px) * 4
                self.pix[di:di + 4] = p[si:si + 4]
        self.background = tuple(self.pix[0:3])

    def to_uv(self, x, y, z):
        tx0, ty0, tx1, ty1 = self.crop
        tx, ty = 32 - y / TILE_YARDS, 32 - x / TILE_YARDS
        u, v = (tx - tx0) / (tx1 - tx0), (ty - ty0) / (ty1 - ty0)
        return (u, v) if self.contains(u, v) else None

    def lua(self):
        tx0, ty0, tx1, ty1 = self.crop
        c0, r0, c1, r1 = int(tx0), int(ty0), int(tx1 - 1e-9), int(ty1 - 1e-9)
        ids = [self.all_tiles.get((r, c), 0) for r in range(r0, r1 + 1) for c in range(c0, c1 + 1)]
        # The crop inside that block of tiles, as texture coordinates of the whole block.
        bw, bh = c1 - c0 + 1, r1 - r0 + 1
        rect = [round((tx0 - c0) / bw, 4), round((ty0 - r0) / bh, 4), round((tx1 - c0) / bw, 4), round((ty1 - r0) / bh, 4)]
        return {'minimap': ids, 'tiles': [bw, bh], 'crop': rect}


# --- Sections -------------------------------------------------------------------------------------

def masks(floor):
    W, H, p, t = floor.w, floor.h, floor.pix, floor.tune
    lum = [(p[4 * i] + p[4 * i + 1] + p[4 * i + 2]) / 3 for i in range(W * H)]
    if isinstance(floor, MinimapFloor):
        bg = floor.background
        drawing = [1 if any(abs(p[4 * i + k] - bg[k]) > 8 for k in range(3)) else 0 for i in range(W * H)]
        return drawing, drawing
    r = t['blur']

    def box(src, horizontal):
        out = [0.0] * (W * H)
        outer, inner = (H, W) if horizontal else (W, H)
        for a in range(outer):
            line = [src[a * W + b] if horizontal else src[b * W + a] for b in range(inner)]
            pre = [0.0]
            for value in line:
                pre.append(pre[-1] + value)
            for b in range(inner):
                lo, hi = max(0, b - r), min(inner, b + r + 1)
                value = (pre[hi] - pre[lo]) / (hi - lo)
                if horizontal:
                    out[a * W + b] = value
                else:
                    out[b * W + a] = value
        return out

    smooth = box(box(lum, True), False)
    parchment = sorted(smooth)[len(smooth) // 2]
    floor_mask = [1 if v >= parchment + t['light'] else 0 for v in smooth]
    drawing = [1 if (f or smooth[i] <= parchment - t['dark']) else 0 for i, f in enumerate(floor_mask)]
    for u0, v0, u1, v1 in floor.spec.get('blank', ()):  # the title banner and other art that isn't the dungeon
        for y in range(int(v0 * H), min(H, int(v1 * H) + 1)):
            for x in range(int(u0 * W), min(W, int(u1 * W) + 1)):
                floor_mask[y * W + x] = drawing[y * W + x] = 0
    return floor_mask, drawing


def to_cells(floor, mask, share, rows):
    W, H = floor.w, floor.h
    cw, ch = W / COLS, H / rows
    cells = [[0] * COLS for _ in range(rows)]
    for r in range(rows):
        for c in range(COLS):
            x0, x1, y0, y1 = int(c * cw), int((c + 1) * cw), int(r * ch), int((r + 1) * ch)
            n = sum(mask[y * W + x] for y in range(y0, y1) for x in range(x0, x1))
            cells[r][c] = 1 if n >= share * (x1 - x0) * (y1 - y0) else 0
    return cells


NEIGHBORS = ((0, 1), (1, 0), (0, -1), (-1, 0), (1, 1), (-1, -1), (1, -1), (-1, 1))
SNAP = 4  # cells an anchor may sit away from the floor (a boss on a ledge, a skull beside the path)


def walk_cells(floor):
    if not hasattr(floor, '_walk'):
        rows = round(COLS * floor.h / floor.w)
        floor_mask, drawing_mask = masks(floor)
        walk = to_cells(floor, floor_mask, floor.tune['floor'], rows)
        drawing = to_cells(floor, drawing_mask, floor.tune['drawing'], rows)
        margin = floor.tune['margin']
        for r in range(rows):
            for c in range(COLS):
                if r < margin or c < margin or r >= rows - margin or c >= COLS - margin:
                    walk[r][c] = drawing[r][c] = 0
        floor._walk = (rows, walk, drawing)
    return floor._walk


def on_floor(floor, u, v):
    rows, walk, _ = walk_cells(floor)
    r0, c0 = min(rows - 1, int(v * rows)), min(COLS - 1, int(u * COLS))
    return any(walk[r][c] for r in range(max(0, r0 - SNAP), min(rows, r0 + SNAP + 1))
               for c in range(max(0, c0 - SNAP), min(COLS, c0 + SNAP + 1)))


def cut(floor, anchors, fallback):
    """Cell grid of section numbers (0 = never fogged) for one floor."""
    rows, walk, drawing = walk_cells(floor)
    owner = [[0] * COLS for _ in range(rows)]
    queue = deque()
    seeds = anchors or ([(fallback, None, None)] if fallback else [])
    for section, u, v in seeds:
        if u is None:  # a floor without anchors belongs to one section
            for r in range(rows):
                for c in range(COLS):
                    if walk[r][c]:
                        owner[r][c] = section
                        queue.append((r, c))
            continue
        r0, c0 = min(rows - 1, int(v * rows)), min(COLS - 1, int(u * COLS))
        best = None
        for r in range(max(0, r0 - SNAP), min(rows, r0 + SNAP + 1)):
            for c in range(max(0, c0 - SNAP), min(COLS, c0 + SNAP + 1)):
                if walk[r][c] and (best is None or (r - r0) ** 2 + (c - c0) ** 2 < best[0]):
                    best = ((r - r0) ** 2 + (c - c0) ** 2, r, c)
        if best is None:
            print(f'    ! anchor of section {section} at {u:.3f},{v:.3f} is not on the floor')
            continue
        _, r, c = best
        if not owner[r][c]:
            owner[r][c] = section
            queue.append((r, c))
    while queue:  # walking distance over the floor: the nearest anchor owns a cell
        r, c = queue.popleft()
        for dr, dc in NEIGHBORS:
            rr, cc = r + dr, c + dc
            if 0 <= rr < rows and 0 <= cc < COLS and walk[rr][cc] and not owner[rr][cc]:
                owner[rr][cc] = owner[r][c]
                queue.append((rr, cc))
    for step in range(floor.tune['spread'] + 1):  # over the drawing around the floor, then one ring more
        grown = [row[:] for row in owner]
        for r in range(rows):
            for c in range(COLS):
                if owner[r][c] or (step < floor.tune['spread'] and not drawing[r][c]):
                    continue
                for dr, dc in NEIGHBORS:
                    rr, cc = r + dr, c + dc
                    if 0 <= rr < rows and 0 <= cc < COLS and owner[rr][cc]:
                        grown[r][c] = owner[rr][cc]
                        break
        owner = grown
    return owner


def pack(owner):
    """Run-length pairs (section, count) over the rows, as the addon's Codec.EncodeInts writes them."""
    runs, flat = [], [s for row in owner for s in row]
    i = 0
    while i < len(flat):
        j = i
        while j < len(flat) and flat[j] == flat[i]:
            j += 1
        runs += [flat[i], j - i]
        i = j
    alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
    out = []
    for n in runs:
        z = n * 2 if n >= 0 else -n * 2 - 1
        while True:
            chunk, z = z % 32, z // 32
            out.append(alphabet[chunk + 32 if z else chunk])
            if not z:
                break
    return ''.join(out)


# --- One instance ---------------------------------------------------------------------------------

def build(instance, spec, data):
    print(f'{instance} {spec["name"]}')
    floors = []
    for i, fs in enumerate(spec['floors']):
        floors.append((ArtFloor if 'uimap' in fs else MinimapFloor)(i + 1, fs, data, instance))

    def place(world):
        for floor in floors:
            uv = floor.to_uv(*world)
            if uv:
                return floor.index, uv[0], uv[1]
        return None

    # Bosses: one section per boss name; difficulty variants share it.
    groups = {}
    for e in data.encounters:
        if e['MapID'] == str(instance):
            g = groups.setdefault(norm(e['Name_lang']), {'name': e['Name_lang'].strip('"'), 'ids': [], 'order': 99,
                                                         'de': data.encounter_names_de.get(e['ID'], e['Name_lang']).strip('"')})
            g['ids'].append(int(e['ID']))
            g['order'] = min(g['order'], int(e['OrderIndex']))
    sections, anchors = [], []
    for key, g in sorted(groups.items(), key=lambda kv: (kv[1]['order'], kv[1]['ids'][0])):
        override = spec.get('bosses', {}).get(g['name'], {})
        if override.get('skip'):
            continue
        # By hand, else retail's journal (its spots are the skulls in the art), else AzerothCore's spawn.
        candidates = []
        if 'at' in override:
            candidates.append(((override['floor'], *override['at']), 'by hand'))
        uimaps = {f.uimap: f.index for f in floors if isinstance(f, ArtFloor)}
        for j in data.journal.get(norm(override.get('npc', g['name'])), []):
            if j['UiMapID'] in uimaps:
                candidates.append(((uimaps[j['UiMapID']], float(j['Map_0']), float(j['Map_1'])), 'journal'))
        for npc in data.npcs.get(norm(override.get('npc', g['name'])), []):
            for world in data.spawns.get((npc, int(instance)), []):
                where = place(world)
                if where:
                    candidates.append((where, 'AzerothCore'))
        spot, source = None, None
        for where, src in candidates:
            if src == 'by hand' or on_floor(floors[where[0] - 1], where[1], where[2]):
                spot, source = where, src
                break
            print(f'  {g["name"]:28}   ({src} spot {where[1]:.3f}, {where[2]:.3f} is off the drawn floor)')
        sections.append({'triggers': sorted(g['ids']), 'label': g['name'], 'de': g['de']})
        if spot:
            anchors.append((len(sections), spot, g['name'], source))
            print(f'  {g["name"]:28} floor {spot[0]} at {spot[1]:.3f}, {spot[2]:.3f} ({source})')
        else:
            print(f'  {g["name"]:28} ! no position: add it to dungeons.py')
    # The entrance, when there is only one (wings that share an instance lift with their first boss).
    entrances = [p for p in (place(w) for w in data.entrances.get(int(instance), [])) if p]
    if 'entrance' in spec:
        entrances = [(spec['entrance']['floor'], *spec['entrance']['at'])]
    if len(entrances) == 1:
        sections.insert(0, {'triggers': ['enter'], 'label': 'Entrance'})
        anchors = [(n + 1, s, l, src) for n, s, l, src in anchors]
        anchors.insert(0, (1, entrances[0], 'Entrance', 'AzerothCore' if 'entrance' not in spec else 'by hand'))
        print(f'  {"Entrance":28} floor {entrances[0][0]} at {entrances[0][1]:.3f}, {entrances[0][2]:.3f}')
    for area_id, a in spec.get('areas', {}).items():
        sections.append({'triggers': [f'area:{area_id}'], 'label': a.get('label', area_id)})
        anchors.append((len(sections), (a['floor'], *a['at']), a.get('label', area_id), 'by hand'))

    grids = []
    for floor in floors:
        mine = [(n, s[1], s[2]) for n, s, _, _ in anchors if s[0] == floor.index]
        later = [n for n, s, _, _ in anchors if s[0] > floor.index]
        earlier = [n for n, s, _, _ in anchors if s[0] < floor.index]
        fallback = floor.spec.get('section') or (min(later) if later else (max(earlier) if earlier else None))
        grids.append(cut(floor, mine, fallback))
    review(instance, spec, floors, grids, anchors, sections)
    used = {s for g in grids for row in g for s in row if s}
    for n, s in enumerate(sections, 1):
        if n not in used:
            print(f'  ! section {s["label"]} has no cells')
    names = {'enUS': data.maps[str(instance)]['MapName_lang'], 'deDE': data.map_names_de.get(str(instance))}
    return {'name': spec['name'], 'names': names, 'sections': sections, 'floors': floors, 'grids': grids}


# --- Output ---------------------------------------------------------------------------------------

def review(instance, spec, floors, grids, anchors, sections):
    os.makedirs(REVIEW, exist_ok=True)
    parts = [f'<h2>{instance} {html.escape(spec["name"])}</h2>']
    for floor, grid in zip(floors, grids):
        rows = len(grid)
        img = bytearray(floor.pix)
        for y in range(floor.h):
            r = min(rows - 1, int(y * rows / floor.h))
            for x in range(floor.w):
                s = grid[r][min(COLS - 1, int(x * COLS / floor.w))]
                i = (y * floor.w + x) * 4
                if s:
                    col = PALETTE[(s - 1) % len(PALETTE)]
                    for k in range(3):
                        img[i + k] = (img[i + k] + col[k]) // 2
                img[i + 3] = 255
        name = f'{instance}_{floor.index}'
        blp.write_png(os.path.join(REVIEW, name + '.png'), floor.w, floor.h, floor.pix)
        blp.write_png(os.path.join(REVIEW, name + '_sections.png'), floor.w, floor.h, img)
        title = (floor.name or {}).get('enUS', f'Floor {floor.index}')
        pins = ''.join(
            f'<span class="pin" style="left:{s[1] * 100:.2f}%;top:{s[2] * 100:.2f}%;'
            f'background:rgb{PALETTE[(n - 1) % len(PALETTE)]}" title="{html.escape(src)}">{html.escape(label)}</span>'
            for n, s, label, src in anchors if s[0] == floor.index)
        parts.append(f'<h3>{html.escape(title)}</h3><div class="pair">'
                     f'<div class="map"><img src="{name}.png"></div>'
                     f'<div class="map"><img src="{name}_sections.png">{pins}</div></div>')
    with open(os.path.join(REVIEW, f'{instance}.html'), 'w', encoding='utf-8') as f:
        f.write('<!doctype html><meta charset="utf-8"><style>body{font:14px sans-serif;background:#222;color:#eee}'
                '.pair{display:flex;gap:12px;flex-wrap:wrap}.map{position:relative;display:inline-block}'
                '.map img{max-width:46vw;display:block}.pin{position:absolute;transform:translate(-50%,-50%);'
                'padding:1px 5px;border-radius:8px;color:#000;font-size:12px;white-space:nowrap;'
                'border:1px solid #000}</style>' + ''.join(parts))


def lua_value(v):
    if isinstance(v, str):
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"') + '"'
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, (list, tuple)):
        return '{ ' + ', '.join(lua_value(x) for x in v) + ' }'
    return str(v)


def names(en, de):
    return f'enUS = {lua_value(en)}, deDE = {lua_value(de or en)}'


def fog_color(floor, grid):
    """The parchment around the dungeon (or the minimap's void): what an unexplored part looks like."""
    if isinstance(floor, MinimapFloor):
        return [round(v / 255, 3) for v in floor.background]
    rows = len(grid)
    fogged = [(r, c) for r in range(rows) for c in range(COLS) if grid[r][c]]
    if not fogged:
        return [0.5, 0.4, 0.25]
    r0, r1 = min(r for r, _ in fogged), max(r for r, _ in fogged)
    c0, c1 = min(c for _, c in fogged), max(c for _, c in fogged)
    samples = [[], [], []]
    for y in range(int(r0 * floor.h / rows), int((r1 + 1) * floor.h / rows), 3):
        for x in range(int(c0 * floor.w / COLS), int((c1 + 1) * floor.w / COLS), 3):
            if not grid[min(rows - 1, y * rows // floor.h)][min(COLS - 1, x * COLS // floor.w)]:
                i = (y * floor.w + x) * 4
                for k in range(3):
                    samples[k].append(floor.pix[i + k])
    if not samples[0]:
        return [0.5, 0.4, 0.25]
    return [round(sorted(ch)[len(ch) // 2] / 255, 3) for ch in samples]


def write_lua(results):
    ids = sorted(results, key=int)
    out = ['local _, ns = ...', '',
           'ns.StaticData = ns.StaticData or {}', '',
           '-- Generated by tools/dungeonmaps/build.py; change tools/dungeonmaps/dungeons.py and run it again.',
           '-- Each dungeon map (docs/dungeon-maps.md), keyed by instanceID (GetInstanceInfo\'s 8th return):',
           '--   sections[n] = what lifts section n: "enter" (arriving), encounter IDs (ENCOUNTER_START or a',
           '--   kill), "area:<areaID>" (a subzone); with the boss\'s name.',
           '--   floors[i].art = the 12 tiles (256 px, 4 x 3, row by row) of a map shown at 1002 x 668, or',
           '--   floors[i].minimap = minimap tiles (512 px, tiles = { columns, rows }) shown cropped to crop',
           '--   (texture coordinates of that block). cells = the floor\'s grid (grid = { columns, rows }) as',
           '--   Codec.EncodeInts of (section, count) runs, row by row; section 0 is never fogged. fog = the',
           '--   color of the parchment around the dungeon.',
           f'-- Sources: Forever {S.FOREVER} (instances, encounters, names, the files), retail {S.RETAIL}',
           f'-- (map tables, floor names, encounter journal), AzerothCore {S.AC_COMMIT[:7]} (spawn and entrance',
           '-- positions).',
           f'ns.StaticData.DungeonMapsVersion = "{",".join(ids)}"',
           'ns.StaticData.DungeonMaps = {']
    for instance in ids:
        res = results[instance]
        out.append(f'    [{instance}] = {{')
        out.append(f'        {names(res["names"]["enUS"], res["names"]["deDE"])},')
        out.append('        sections = {')
        for sec in res['sections']:
            triggers = ', '.join(lua_value(t) for t in sec['triggers'])
            label = f', {names(sec["label"], sec.get("de"))}' if sec['triggers'] != ['enter'] else ''
            out.append(f'            {{ {triggers}{label} }},')
        out.append('        },')
        out.append('        floors = {')
        for floor, grid in zip(res['floors'], res['grids']):
            out.append('            {')
            if floor.name:
                out.append(f'                {names(floor.name.get("enUS", ""), floor.name.get("deDE"))},')
            for k, v in floor.lua().items():
                out.append(f'                {k} = {lua_value(v)},')
            out.append(f'                fog = {lua_value(fog_color(floor, grid))},')
            out.append(f'                grid = {{ {COLS}, {len(grid)} }},')
            out.append(f'                cells = "{pack(grid)}",')
            out.append('            },')
        out.append('        },')
        out.append('    },')
    out.append('}')
    with open(OUT_LUA, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out) + '\n')
    print('wrote', os.path.relpath(OUT_LUA))


def main():
    data = Data()
    wanted = sys.argv[1:] or list(DUNGEONS)
    results = {}
    for instance in DUNGEONS:
        if instance in wanted:
            results[instance] = build(instance, DUNGEONS[instance], data)
    if not sys.argv[1:]:
        write_lua(results)
    print('review pages in', os.path.relpath(REVIEW))


if __name__ == '__main__':
    main()
