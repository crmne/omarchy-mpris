import QtQuick

// Omarchy only hands the trusted built-in bar its plugin services. Custom and
// cloned bars get a restricted shell whose serviceFor() returns null, so the
// widget would never render there. Fall back to a private service instance.
Item {
  id: root

  property var bar: null
  property string serviceId: ""
  property Component fallback: null

  readonly property var hostedService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(serviceId) || null : null
  readonly property var service: hostedService || fallbackLoader.item || null

  Loader {
    id: fallbackLoader
    active: !!root.bar && !root.hostedService && root.fallback !== null
    sourceComponent: root.fallback
  }
}
