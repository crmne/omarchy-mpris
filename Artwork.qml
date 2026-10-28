import QtQuick
import Quickshell.Io
import "Artwork.js" as Artwork

// The player's album art, as a source Image can load without trusting the
// server it came from. Remote covers are downloaded by bin/artwork with a hard
// byte limit and loaded from its private cache; covers on disk are passed
// through once the helper has checked their size. See Artwork.js.
Item {
  id: root

  // What the player advertises (mpris:artUrl).
  property string url: ""
  // Nothing is fetched while this is false.
  property bool active: true
  property bool allowHttp: false

  readonly property string requestedUrl: active ? Artwork.allowedUrl(url, allowHttp) : ""
  // Empty until the helper has vouched for the current URL.
  readonly property string source: resolved.url === requestedUrl ? resolved.source : ""

  // Which URL the helper last answered for, and what it answered, set
  // together so `source` never pairs one track's URL with another's cover.
  property var resolved: ({ url: "", source: "" })
  property string pendingUrl: ""
  property int request: 0

  // The helper ships next to this file, so the plugin works the same whether
  // it was installed by `omarchy plugin add` or symlinked from a checkout.
  readonly property string helperPath: {
    var path = String(Qt.resolvedUrl("bin/artwork"))
    return path.indexOf("file://") === 0 ? path.substring(7) : path
  }
  // Called explicitly rather than through the shebang: the shell inherits a
  // PATH where `python3` may be a version manager's shim.
  readonly property string python: "/usr/bin/python3"

  onRequestedUrlChanged: resolve()
  Component.onCompleted: resolve()

  function resolve() {
    proc.running = false
    request++
    pendingUrl = ""
    if (!requestedUrl || requestedUrl === resolved.url) return
    pendingUrl = requestedUrl
    var run = Artwork.invocation({
      python: python, helper: helperPath, url: requestedUrl,
      allowHttp: allowHttp, request: request
    })
    proc.command = run.command
    proc.environment = run.environment
    var wanted = request
    Qt.callLater(function () {
      if (root.request === wanted) proc.running = true
    })
  }

  // A run that was stopped for the next track still finishes its stream;
  // only the answer to the current request counts.
  function finish(raw) {
    if (!pendingUrl || Artwork.requestOf(raw) !== String(request)) return
    var url = pendingUrl
    pendingUrl = ""
    resolved = { url: url, source: Artwork.sourceFromOutput(raw, request) }
  }

  Process {
    id: proc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finish(text)
    }
  }
}
