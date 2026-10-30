import QtQuick
import QtTest
import "../Transport.js" as Transport

TestCase {
  name: "Transport"

  function player(canSeek) {
    return { canSeek: canSeek, offsets: [], seek: function(offset) { this.offsets.push(offset) } }
  }

  function test_seeksPlayersThatAdvertiseIt() {
    var subject = player(true)
    verify(Transport.seekBy(subject, -Transport.SEEK_STEP))
    verify(Transport.seekBy(subject, Transport.SEEK_STEP))
    compare(subject.offsets, [-10, 10])
  }

  function test_leavesOtherPlayersAlone() {
    var subject = player(false)
    verify(!Transport.seekBy(subject, 10))
    compare(subject.offsets, [])
    verify(!Transport.seekBy(null, 10))
  }

  function test_ignoresOffsetsThatMoveNothing() {
    var subject = player(true)
    verify(!Transport.seekBy(subject, 0))
    verify(!Transport.seekBy(subject, NaN))
    verify(!Transport.seekBy(subject, Infinity))
    verify(!Transport.seekBy(subject, "ten"))
    compare(subject.offsets, [])
    // IPC arguments can arrive as text.
    verify(Transport.seekBy(subject, "-10"))
    compare(subject.offsets, [-10])
  }
}
