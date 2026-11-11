# Support OpenMap through its public API

OpenMap replaces the world map with one stitched Azeroth: the canvas belongs to a host map that
follows the view, and OpenMap's art covers everything below its own frame levels. Footsteps and markers
would vanish under it, or stop at the host map's edge. While the stitched map is up, Wayscribe draws
above `OpenMapAPI.ArtTopLevel()` and places every point with `OpenMapAPI.CanvasFromWorldPos`, so trails
and markers show on every continent of the stitched world and run past the host map. It is detected by
capability (`OpenMapAPI`, major 1, version 2 or later), never by addon name.

## Considered Options

- **Only draw above OpenMap's art, keep clipping to the host map.** Trails would be cut at whatever
  zone the view sits on. Rejected.
- **Copy OpenMap's region math (`ns.MapWorld`) for a fast per-continent transform.** That's internal
  to OpenMap and changes when it does. Rejected: one API call per point, spread over frames by the
  drawing budget, is the price.

## Consequences

Redraws on the stitched map happen only when the host map changes, the stitched mode toggles or the
zoom settles, not on every pan: the whole world is drawn once and the canvas carries it.
