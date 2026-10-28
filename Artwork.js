// Album art goes through bin/artwork before Qt sees it. Given an http(s) URL,
// Qt's Image buffers the whole response before decoding it, so a cover server
// answering with gigabytes would exhaust the shell's memory. The helper
// downloads with a hard byte limit into a private cache and prints a local
// file instead; covers already on disk are only size-checked.
//
// Kept free of QML types so the rules can be tested on their own.

// bin/artwork prints one short JSON line. `head` cuts it off one byte past
// this, and anything that long is refused whole.
var MAX_OUTPUT_BYTES = 4096
// The helper gives itself 20 seconds; `timeout` stops it a little later if it
// does not stop itself.
var TIMEOUT_SECONDS = 25
var ENV = "ARTWORK_URL"
// Echoed back by the helper, so output from a run that was superseded by the
// next track can never be taken for the current one.
var REQUEST_ENV = "ARTWORK_REQUEST"
// bin/artwork refuses anything longer, so it is not worth a process.
var MAX_URL_CHARS = 4096

// The URL worth asking the helper about, or "" for none. Players can name any
// URL, and loading one is a request nobody asked for, so only covers on disk
// and https (plus plain http where the caller allows it) are considered.
function allowedUrl(url, allowHttp) {
  var text = String(url || "")
  if (text.length > MAX_URL_CHARS) return ""
  if (/^file:\/\//i.test(text) || /^https:\/\//i.test(text)) return text
  if (allowHttp && /^http:\/\//i.test(text)) return text
  return ""
}

// How to run the helper for one URL: a command and an environment.
//
// The URL names the track, and a process's arguments are readable by every
// user on the machine, so it travels in the environment, which only this
// user can read. The shell text is a constant with numbers in it, never
// anything from the player.
function invocation(options) {
  var opts = options || {}
  var script = "/usr/bin/timeout -k 2 " + TIMEOUT_SECONDS + " \"$@\""
    + " | /usr/bin/head -c " + (MAX_OUTPUT_BYTES + 1)
  var command = ["/usr/bin/sh", "-c", script, "artwork",
    String(opts.python || "/usr/bin/python3"), String(opts.helper || "")]
  if (opts.allowHttp) command.push("--allow-http")
  var environment = {}
  environment[ENV] = String(opts.url || "")
  environment[REQUEST_ENV] = String(opts.request || "")
  return { command: command, environment: environment }
}

// What the helper printed, as an object, or null when it printed nothing
// usable. Output past the limit means it did not respect its own shape (the
// shell cuts it off one byte past), so it is refused whole rather than parsed.
function parseOutput(raw) {
  var text = String(raw || "")
  if (text.length > MAX_OUTPUT_BYTES) return null
  var payload
  try {
    payload = JSON.parse(text.trim())
  } catch (error) {
    return null
  }
  return payload && typeof payload === "object" ? payload : null
}

// Which request the helper was answering, or "" when it did not say.
function requestOf(raw) {
  var payload = parseOutput(raw)
  return payload && typeof payload.request === "string" ? payload.request : ""
}

// The local source the helper printed for `request`, or "" when there is none.
// Only a file:// URL is accepted, so whatever goes wrong, Image is never
// handed something that would reach the network.
function sourceFromOutput(raw, request) {
  var payload = parseOutput(raw)
  if (!payload || payload.ok !== true || typeof payload.source !== "string") return ""
  if (payload.request !== String(request || "")) return ""
  return /^file:\/\//i.test(payload.source) ? payload.source : ""
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_OUTPUT_BYTES: MAX_OUTPUT_BYTES,
    TIMEOUT_SECONDS: TIMEOUT_SECONDS,
    ENV: ENV,
    MAX_URL_CHARS: MAX_URL_CHARS,
    REQUEST_ENV: REQUEST_ENV,
    allowedUrl: allowedUrl,
    invocation: invocation,
    parseOutput: parseOutput,
    requestOf: requestOf,
    sourceFromOutput: sourceFromOutput
  }
}
