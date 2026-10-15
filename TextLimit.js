.pragma library

// Track metadata comes from any MPRIS player. Count and cut it by Unicode
// code point, so an emoji or other astral character is never split into a
// lone UTF-16 surrogate that renders as a broken glyph. (Qt's JavaScript
// engine iterates strings by UTF-16 unit, so walk the pairs explicitly.)
function codePoints(value) {
  var result = []
  for (var i = 0; i < value.length; i++) {
    var code = value.charCodeAt(i)
    var next = value.charCodeAt(i + 1)
    if (code >= 0xD800 && code <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF) {
      result.push(value.substr(i, 2))
      i++
    } else {
      result.push(value.charAt(i))
    }
  }
  return result
}

function limitCharacters(text, maximum) {
  var value = String(text || "")
  var limit = Math.max(1, Number(maximum) || 1)
  if (value.length <= limit) return value
  var characters = codePoints(value)
  if (characters.length <= limit) return value
  return characters.slice(0, Math.max(1, limit - 1)).join("").trim() + "…"
}
