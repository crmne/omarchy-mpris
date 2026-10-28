import QtQuick
import QtTest
import "../Artwork.js" as Artwork

TestCase {
  name: "Artwork"

  function test_onlyDiskAndHttpsCoversAreConsidered() {
    compare(Artwork.allowedUrl("https://i.scdn.co/image/abc", false), "https://i.scdn.co/image/abc")
    compare(Artwork.allowedUrl("file:///tmp/cover.png", false), "file:///tmp/cover.png")
    compare(Artwork.allowedUrl("http://example.com/a.png", false), "")
    compare(Artwork.allowedUrl("http://example.com/a.png", true), "http://example.com/a.png")
    compare(Artwork.allowedUrl("ftp://example.com/a.png", true), "")
    compare(Artwork.allowedUrl("data:image/png;base64,AAAA", true), "")
    compare(Artwork.allowedUrl("", true), "")
    compare(Artwork.allowedUrl("https://example.com/" + "a".repeat(Artwork.MAX_URL_CHARS), true), "")
  }

  function test_theUrlTravelsInTheEnvironmentNotTheCommandLine() {
    var url = "https://example.com/cover.png?track=secret"
    var run = Artwork.invocation({ python: "/usr/bin/python3", helper: "/plugin/bin/artwork",
      url: url, allowHttp: true, request: 4 })
    compare(run.environment[Artwork.ENV], url)
    compare(run.environment[Artwork.REQUEST_ENV], "4")
    for (var i = 0; i < run.command.length; i++)
      verify(run.command[i].indexOf("secret") === -1, run.command[i])
    compare(run.command.slice(3), ["artwork", "/usr/bin/python3", "/plugin/bin/artwork", "--allow-http"])
    // Whatever the helper prints is cut off just past the limit.
    verify(run.command[2].indexOf("/usr/bin/head -c " + (Artwork.MAX_OUTPUT_BYTES + 1)) !== -1)
    verify(run.command[2].indexOf("/usr/bin/timeout") === 0)
  }

  function test_onlyALocalFileForTheCurrentRequestIsLoaded() {
    var ok = JSON.stringify({ ok: true, request: "4", source: "file:///home/me/.cache/x" })
    compare(Artwork.sourceFromOutput(ok, 4), "file:///home/me/.cache/x")
    compare(Artwork.requestOf(ok), "4")
    // An answer to the previous track's request.
    compare(Artwork.sourceFromOutput(ok, 5), "")
    // Never a source that would reach the network.
    compare(Artwork.sourceFromOutput(JSON.stringify({ ok: true, request: "4",
      source: "https://example.com/a.png" }), 4), "")
    compare(Artwork.sourceFromOutput(JSON.stringify({ ok: false, request: "4",
      code: "too_large" }), 4), "")
    compare(Artwork.sourceFromOutput("", 4), "")
    compare(Artwork.sourceFromOutput("not json", 4), "")
    compare(Artwork.sourceFromOutput(ok + " ".repeat(Artwork.MAX_OUTPUT_BYTES), 4), "")
  }
}
