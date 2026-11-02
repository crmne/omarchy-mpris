.pragma library

// Seconds the seek buttons move the playhead.
var SEEK_STEP = 10

// Seek only players that advertise it, and only by a real, nonzero offset.
// Returns whether the seek was sent; the player clamps at either end.
function seekBy(player, seconds) {
  var offset = Number(seconds)
  if (!player || !player.canSeek || !isFinite(offset) || offset === 0) return false
  player.seek(offset)
  return true
}
