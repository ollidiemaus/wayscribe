"""The dungeons that get a map, keyed by Forever's instanceID (Map.db2), with what can't be looked up.

Per dungeon:
- floors: retail dungeon maps (`uimap`) in their order, or for Forever's new instances a crop of the
  minimap tiles (`minimap = (tx0, ty0, tx1, ty1)` in ADT tile units: tile x = 32 - worldY / 533.33,
  tile y = 32 - worldX / 533.33). Per floor, `blank` lists rectangles (u0, v0, u1, v1) that are art,
  not dungeon (the title banner), and `tune` overrides build.DEFAULTS where the art needs it.
- bosses: per encounter name (as in Forever's DungeonEncounter), `npc` to look up another creature,
  `at = (u, v)` with `floor` to place it by hand, or `skip`.
- entrance: a hand-placed entrance where AzerothCore has none (Forever's new instances).
- areas: areaID -> {floor, at, label}, for subzones inside the instance.
"""

DUNGEONS = {
    '389': {
        'name': 'Ragefire Chasm',
        'floors': [{'uimap': 213, 'blank': [(0.04, 0.03, 0.6, 0.16)]}],
    },
    '43': {
        'name': 'Wailing Caverns',
        'floors': [{'uimap': 279, 'blank': [(0.47, 0.04, 0.96, 0.17)]}],
    },
    '36': {
        'name': 'The Deadmines',
        'floors': [
            {'uimap': 291, 'blank': [(0.34, 0.02, 0.73, 0.15), (0.47, 0.14, 0.67, 0.46)]},
            {'uimap': 292, 'blank': [(0.31, 0.02, 0.70, 0.15)]},
        ],
        'bosses': {'Miner Johnson': {'skip': True}},  # a rare spawn: his corner would never lift for most
    },
    '3065': {
        # Placed by the route in Warcraft Tavern's guide on the minimap tiles: you arrive in the south
        # hall, Faldrim rests in the west wing, the lava cavern is east, Plunder walks the main hall,
        # and Durgen waits in the round Reliquary of Kings beyond the bridge. To be checked in game.
        'name': 'The Hall of Thanes',
        'floors': [{'minimap': (31.45, 30.75, 32.6, 32.3)}],
        'entrance': {'floor': 1, 'at': (0.475, 0.890)},
        'bosses': {
            'Faldrim Anvilmar': {'floor': 1, 'at': (0.220, 0.739)},
            'Infurnus': {'floor': 1, 'at': (0.781, 0.612)},
            'Plunder': {'floor': 1, 'at': (0.475, 0.587)},
            'Durgen Dirgehammer': {'floor': 1, 'at': (0.478, 0.386)},
        },
    },
}
