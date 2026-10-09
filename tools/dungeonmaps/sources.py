"""The inputs of the dungeon map data, downloaded once into .cache/ and pinned to exact versions.

- Forever's client tables and files (wago.tools, build FOREVER): instances, encounters, areas, the
  map tiles themselves. The addon shows these files by ID; nothing here is shipped.
- Retail's map tables (wago.tools, build RETAIL): which file is which tile of a dungeon map, where a
  floor sits in the world, the floors' names, and where the encounter journal puts each boss.
  Forever's own tables don't list dungeon maps (docs/dungeon-maps.md).
- AzerothCore's world database (commit AC_COMMIT): where the old bosses stand and where a dungeon's
  entrance puts the player, as world coordinates. Only these facts are used.
"""
import csv
import io
import os
import re
import subprocess

FOREVER = '1.60.1.70291'
RETAIL = '12.1.0.69933'
AC_COMMIT = 'a05a04313eadcc61b38aaa1c9a7a9cd56395f279'

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, '.cache')


def _fetch(url, path):
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        subprocess.run(['curl', '-s', '-f', '-L', '-o', path, url], check=True)
    return path


def table(name, build, locale=None):
    """A DB2 table as a list of dicts (column name -> string)."""
    suffix = f'&locale={locale}' if locale else ''
    path = _fetch(f'https://wago.tools/db2/{name}/csv?build={build}{suffix}',
                  os.path.join(CACHE, 'db2', build, f'{name}{"." + locale if locale else ""}.csv'))
    with open(path, encoding='utf-8') as f:
        text = f.read()
    if text.startswith('{'):
        raise RuntimeError(f'{name} ({build}): {text[:200]}')
    return list(csv.DictReader(io.StringIO(text)))


def client_file(file_id):
    """Path of one file of Forever's client, by file ID."""
    path = os.path.join(CACHE, 'files', f'{file_id}.bin')
    _fetch(f'https://wago.tools/api/casc/{file_id}?version={FOREVER}', path)
    if os.path.getsize(path) == 0:
        raise RuntimeError(f'file {file_id} is not in build {FOREVER}')
    return path


def _ac_file(name):
    return _fetch(f'https://raw.githubusercontent.com/azerothcore/azerothcore-wotlk/{AC_COMMIT}'
                  f'/data/sql/base/db_world/{name}.sql', os.path.join(CACHE, 'ac', f'{name}.sql'))


_VALUE = re.compile(r"\s*(NULL|'(?:[^'\\]|\\.)*'|-?[\d.eE+-]+)\s*(,|\))")


def _parse_tuple(line):
    """One `(a,b,'c',...)` row of a mysqldump INSERT, as strings (None for NULL)."""
    line = line.strip()
    if not line.startswith('('):
        return None
    values, pos = [], 1
    while pos < len(line):
        m = _VALUE.match(line, pos)
        if not m:
            return None
        raw = m.group(1)
        if raw == 'NULL':
            values.append(None)
        elif raw.startswith("'"):
            values.append(re.sub(r"\\(.)", r"\1", raw[1:-1]))
        else:
            values.append(raw)
        pos = m.end()
        if m.group(2) == ')':
            break
    return values


def ac_rows(name):
    """The rows of one AzerothCore table as dicts, by the column names of its CREATE TABLE."""
    columns, rows = [], []
    with open(_ac_file(name), encoding='utf-8', errors='replace') as f:
        in_create = False
        for line in f:
            if line.startswith('CREATE TABLE'):
                in_create = True
                continue
            if in_create:
                m = re.match(r'\s*`(\w+)`', line)
                if m:
                    columns.append(m.group(1))
                elif not line.strip().startswith(('PRIMARY', 'KEY', 'UNIQUE', 'FULLTEXT', 'CONSTRAINT')):
                    in_create = False
                continue
            values = _parse_tuple(line)
            if values and len(values) == len(columns):
                rows.append(dict(zip(columns, values)))
    return rows
