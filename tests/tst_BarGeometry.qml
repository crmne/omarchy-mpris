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

  Component {
    id: notchComponent
    Item {
      width: 1600
      height: 26
      property alias ownSlot: media
      property alias endSlot: end
      property alias sections: sections
      property alias widget: media.activeItem

      function place() {
        media.x = width - 8 - media.width
        sections.x = media.x - 4 - sections.width
      }

      Slot { region: "left"; x: 8; width: 300 }
      // Omarchy 4.5 anchors the center sections 4 px left of the right
      // section where a display notch covers the middle of the bar.
      Item {
        id: sections
        property bool besideRight: true
        width: end.width
        height: 26
        Slot { id: end; region: "centerEnd"; width: 154 }
      }
      Slot { id: media; width: 0 }
    }
  }

  // Omarchy 4.5's horizontal bar: the left and right sections held 8 px in
  // from its ends, and the center sections, where the box is centered and
  // centerBegin and centerEnd hang off its edges. Beside a display notch the
  // three run on 4 px left of the right section. place() lays every slot out
  // from the widths, as the host does, so a budget that followed the
  // widget's own width would change between widths.
  Component {
    id: centerComponent
    Item {
      id: bar
      width: 1600
      height: 26
      property alias sections: sections
      property alias leftSlot: leftSlot
      property alias rightSlot: rightSlot
      property alias beginSlot: beginSlot
      property alias clockSlot: clockSlot
      property alias endSlot: endSlot
      property alias ownSlot: media
      property alias widget: media.activeItem
      property var lists: ({ centerBegin: [beginSlot], center: [clockSlot], centerEnd: [endSlot] })

      function sum(list) {
        var total = 0
        for (var slot of list) total += slot.width
        return total
      }

      function place() {
        leftSlot.x = 8
        rightSlot.x = width - 8 - rightSlot.width
        var begin = sum(lists.centerBegin)
        var box = sum(lists.center)
        if (sections.besideRight) {
          sections.width = begin + box + sum(lists.centerEnd)
          sections.x = rightSlot.x - 4 - sections.width
        } else {
          sections.width = width
          sections.x = 0
        }
        var start = sections.besideRight ? begin : Math.round((sections.width - box) / 2)
        var x = start
        for (var slot of lists.center) { slot.x = x; x += slot.width }
        for (slot of lists.centerEnd) { slot.x = x; x += slot.width }
        x = start
        for (var i = lists.centerBegin.length - 1; i >= 0; i--) {
          x -= lists.centerBegin[i].width
          lists.centerBegin[i].x = x
        }
      }

      // Puts this widget in a section, at an index of its list.
      function move(region, index) {
        for (var key in lists) lists[key] = lists[key].filter(function(slot) { return slot !== media })
        lists[region].splice(index, 0, media)
        media.region = region
      }

      Slot { id: leftSlot; region: "left"; width: 300 }
      Item {
        id: sections
        property bool besideRight: false
        height: 26
        Slot { id: beginSlot; region: "centerBegin"; width: 60 }
        Slot { id: clockSlot; region: "center"; width: 154 }
        Slot { id: endSlot; region: "centerEnd"; width: 60 }
        Slot { id: media; region: "centerEnd"; width: 0 }
      }
      Slot { id: rightSlot; region: "right"; width: 200 }
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

  function centerFixture(region, index) {
    var scene = createTemporaryObject(centerComponent, testCase)
    scene.move(region, index)
    return scene
  }

  // The budget for each of the widget's widths, laid out again each time.
  function budgets(scene, widths) {
    var result = []
    for (var width of widths) {
      scene.ownSlot.width = width
      scene.place()
      result.push(budget(scene))
    }
    return result
  }

  function test_centerEnd() {
    // From the box's right edge to the right section, less what follows it.
    for (var index of [0, 1]) {
      var scene = centerFixture("centerEnd", index)
      compare(Geometry.hostSlot(scene.widget), scene.ownSlot)
      compare(budgets(scene, [0, 300, 31, 447, 600]), [447, 447, 447, 447, 447])
    }
    scene.rightSlot.width = 400
    compare(budgets(scene, [0, 247]), [247, 247])
  }

  function test_centerBegin() {
    // From the box's left edge to the left section, less what precedes it.
    for (var index of [0, 1]) {
      var scene = centerFixture("centerBegin", index)
      compare(budgets(scene, [0, 300, 31, 347, 600]), [347, 347, 347, 347, 347])
    }
    scene.leftSlot.width = 400
    compare(budgets(scene, [0, 247]), [247, 247])
  }

  function test_centerBox() {
    // The box grows both ways, so it gets twice the room on its tighter side,
    // less the clock it shares the box with and the host's rounding.
    var scene = centerFixture("center", 1)
    compare(budgets(scene, [0, 300, 31, 693, 694, 900]), [693, 693, 693, 693, 693, 693])
    scene.leftSlot.width = 500
    compare(budgets(scene, [0, 293, 31]), [293, 293, 293])
    scene.endSlot.width = 300
    scene.leftSlot.width = 300
    compare(budgets(scene, [0, 413, 64]), [413, 413, 413])
  }

  function test_centerSectionsBesideNotch() {
    // All four sections grow toward the start of the bar as one, up to the
    // left section, with the center sections' gap before the right one.
    for (var region of ["centerBegin", "center", "centerEnd"]) {
      var scene = centerFixture(region, 0)
      scene.sections.besideRight = true
      compare(budgets(scene, [0, 400, 31, 794, 900]), [794, 794, 794, 794, 794])
    }
  }

  function test_centerSectionsElsewhere() {
    // Hosts without Omarchy 4.5's center sections keep the full layout there.
    var scene = fixture()
    for (var region of ["centerBegin", "center", "centerEnd"]) {
      scene.ownSlot.region = region
      compare(Geometry.hostSlot(scene.widget), scene.ownSlot)
      compare(budget(scene), 100000)
    }
  }

  function test_traySection() {
    // The tray's drawer shows its widgets only while it is open.
    var scene = fixture()
    scene.ownSlot.region = "tray"
    compare(Geometry.hostSlot(scene.widget), scene.ownSlot)
    compare(budget(scene), 100000)
  }

  function test_centerSectionsAreObstacles() {
    var scene = fixture()
    for (var region of ["centerBegin", "centerEnd"]) {
      scene.clockSlot.region = region
      compare(budget(scene), 113)
    }
  }

  function test_centerSectionsBesideRight() {
    var scene = createTemporaryObject(notchComponent, testCase)
    // The centerEnd slot moves with this widget's width, so it must not
    // become a budget of the current width minus the gap.
    for (var width of [0, 406, 32, 1114, 0]) {
      scene.ownSlot.width = width
      scene.place()
      compare(budget(scene), 1114)
    }
    scene.endSlot.width = 254
    scene.sections.width = 254
    scene.place()
    compare(budget(scene), 1014)
    // Without the notch the sections stay put and remain an obstacle.
    scene.sections.besideRight = false
    scene.ownSlot.width = 0
    scene.place()
    compare(budget(scene), 0)
  }

  function test_missingGeometry() {
    var scene = fixture()
    compare(Geometry.widthBudget(scene.widget, null, 8, 8), 0)
    scene.width = 0
    compare(budget(scene), 0)
    scene.width = 1600
    // Outside any slot this file knows, the widget keeps its full layout
    // rather than hiding where nothing would bring it back (#25).
    scene.widget.parent = testCase
    compare(budget(scene), 100000)
    scene.widget.parent = scene.ownSlot
    scene.ownSlot.region = "middle"
    compare(budget(scene), 100000)
  }

  function test_fractionalGeometry() {
    var scene = fixture()
    scene.sibling.width += 0.5
    compare(budget(scene), 112)
  }
}
