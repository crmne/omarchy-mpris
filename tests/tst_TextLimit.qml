import QtQuick
import QtTest
import "../TextLimit.js" as TextLimit

TestCase {
  name: "TextLimit"

  function hasLoneSurrogate(text) {
    for (var i = 0; i < text.length; i++) {
      var code = text.charCodeAt(i)
      if (code >= 0xD800 && code <= 0xDBFF) {
        var low = text.charCodeAt(i + 1)
        if (!(low >= 0xDC00 && low <= 0xDFFF)) return true
        i++
      } else if (code >= 0xDC00 && code <= 0xDFFF) {
        return true
      }
    }
    return false
  }

  function test_keepsShortText() {
    compare(TextLimit.limitCharacters("Short title", 48), "Short title")
    compare(TextLimit.limitCharacters("", 48), "")
    compare(TextLimit.limitCharacters(null, 48), "")
  }

  function test_truncatesWithEllipsis() {
    compare(TextLimit.limitCharacters("abcdefghijkl", 10), "abcdefghi…")
    compare(TextLimit.limitCharacters("abcd efghij", 6), "abcd…")
  }

  function test_countsAstralCharactersOnce() {
    var text = "🎵🎵🎵🎵🎵"
    compare(text.length, 10)
    compare(TextLimit.limitCharacters(text, 5), text)
  }

  function test_neverSplitsSurrogatePairs() {
    var text = "Night Drive 🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙"
    for (var limit = 10; limit <= 22; limit++) {
      var result = TextLimit.limitCharacters(text, limit)
      verify(!hasLoneSurrogate(result), "limit " + limit + ": " + escape(result))
      compare(TextLimit.codePoints(result).length <= limit, true)
    }
    compare(TextLimit.limitCharacters("ab🌙cd", 4), "ab🌙…")
  }
}
