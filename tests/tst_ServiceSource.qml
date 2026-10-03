import QtQuick
import QtTest
import "../"

TestCase {
  id: testCase
  name: "ServiceSource"

  property int fallbackCount: 0

  QtObject { id: hosted; property bool hasMedia: true }

  // Built-in bar: the shell provides the service.
  QtObject {
    id: trustedBar
    property var shell: QtObject {
      function serviceFor(id) { return id === "crmne.mpris" ? hosted : null }
    }
  }

  // Custom or cloned bar: the restricted shell has no services (#5).
  QtObject {
    id: restrictedBar
    property var shell: QtObject {
      function serviceFor(id) { return null }
    }
  }

  QtObject { id: shelllessBar; property var shell: null }

  Component {
    id: fallbackComponent
    QtObject {
      property bool hasMedia: true
      Component.onCompleted: testCase.fallbackCount++
    }
  }

  Component {
    id: sourceComponent
    ServiceSource {
      serviceId: "crmne.mpris"
      fallback: fallbackComponent
    }
  }

  function source(bar) {
    return createTemporaryObject(sourceComponent, testCase, { bar: bar })
  }

  function init() {
    fallbackCount = 0
  }

  function test_hostedService() {
    var subject = source(trustedBar)
    compare(subject.service, hosted)
    compare(fallbackCount, 0)
  }

  function test_restrictedShellFallsBack() {
    var subject = source(restrictedBar)
    verify(subject.service !== null)
    verify(subject.service !== hosted)
    compare(subject.service.hasMedia, true)
    compare(fallbackCount, 1)
  }

  function test_missingShellFallsBack() {
    var subject = source(shelllessBar)
    verify(subject.service !== null)
    compare(fallbackCount, 1)
  }

  function test_waitsForBar() {
    var subject = source(null)
    compare(subject.service, null)
    compare(fallbackCount, 0)
    subject.bar = restrictedBar
    verify(subject.service !== null)
    subject.bar = trustedBar
    compare(subject.service, hosted)
  }
}
