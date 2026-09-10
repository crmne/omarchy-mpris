import QtQuick
import QtTest
import "../BarGeometry.js" as Geometry

TestCase {
  id: testCase
  name: "BarGeometry"
  when: windowShown
  visible: true

  component Slot: Item {
    property string region: "right"
    property Item activeItem: Item { parent: loader }
    height: 26
    Item { id: loader; anchors.fill: parent }
  }

  Component {
    id: fixtureComponent
    Item {
      width: 1600
      height: 26
      property alias ownSlot: media
      property alias clockSlot: clock
      property alias sibling: tray
      property alias hiddenGroup: hidden
      property alias nestedSlot: nested
      property alias widget: media.activeItem

      Slot { id: clock; region: "center"; x: 734; width: 154 }
      // Match the host's nested layout/row/slot/loader hierarchy.
      Item {
        Item {
          Slot { id: tray; x: 603; width: 135 }
          Slot {
            id: media
            x: 738
            width: 406
            // Descendants of a widget must not count as bar obstacles.
            Slot { id: nested; region: "center"; x: 400; width: 1000 }
          }
          Slot { x: 1144; width: 448 }
        }
      }
      Item {
        id: hidden
        visible: false
        Slot { region: "center"; x: 0; width: 1600 }
      }
    }
  }

  function fixture() {
    return createTemporaryObject(fixtureComponent, testCase)
  }

  function budget(scene) {
    return Geometry.widthBudget(scene.widget, scene, 8, 8)
  }

  function test_restrictedApi() {
    var scene = fixture()
    // No bar.moduleSlots, slotWindow, or sameWindow is available.
    compare(Geometry.hostSlot(scene.widget), scene.ownSlot)
    compare(budget(scene), 113)
  }

  function test_independentWindows() {
    var narrow = fixture()
    var wide = fixture()
    wide.width = 2880
    wide.clockSlot.x = 1374
    compare(budget(narrow), 113)
    compare(budget(wide), 753)
  }

  function test_ownWidthDoesNotFeedBack() {
    var scene = fixture()
    for (var width of [406, 121, 32, 0, 406]) {
      scene.ownSlot.width = width
      compare(budget(scene), 113)
    }
  }

  function test_changedNeighbors() {
    var scene = fixture()
    scene.sibling.width += 50
    compare(budget(scene), 63)
    scene.clockSlot.width += 200
    compare(budget(scene), 0)
    scene.clockSlot.visible = false
    compare(budget(scene), 943)
    scene.clockSlot.visible = true
    scene.clockSlot.width = 154
    scene.sibling.width = 135
    compare(budget(scene), 113)
  }

  function test_hiddenAndNestedSlots() {
    var scene = fixture()
    compare(budget(scene), 113)
    scene.hiddenGroup.visible = true
    compare(budget(scene), 0)
    scene.hiddenGroup.visible = false
    scene.sibling.activeItem.visible = false
    compare(budget(scene), 248)
  }

  function test_leftSection() {
    var scene = fixture()
    scene.ownSlot.region = "left"
    compare(budget(scene), 587)
    scene.sibling.visible = false
    compare(budget(scene), 718)
  }

  function test_missingGeometry() {
    var scene = fixture()
    compare(Geometry.widthBudget(scene.widget, null, 8, 8), 0)
    scene.width = 0
    compare(budget(scene), 0)
    scene.width = 1600
    scene.widget.parent = testCase
    compare(budget(scene), 0)
  }

  function test_fractionalGeometry() {
    var scene = fixture()
    scene.sibling.width += 0.5
    compare(budget(scene), 112)
  }
}
