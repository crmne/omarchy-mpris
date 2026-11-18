// Measure only visual slots in this bar window. Third-party PluginBarApi
// objects no longer expose the host's moduleSlots or window helpers.
//
// Omarchy 4.5 holds the left and right sections to the ends of the bar and
// centers the center section's box, with centerBegin and centerEnd hanging
// off its two edges. Where a display notch covers the middle of the bar, the
// three center sections run on just left of the right one instead
// (CenterSections with besideRight). The tray section lives in the tray's
// drawer.
var REGIONS = { left: true, centerBegin: true, center: true, centerEnd: true, right: true, tray: true }

// The budget of a widget whose room this file cannot work out: its full
// layout, rather than hiding it where nothing would bring it back.
var UNMEASURED = 100000

function isSlot(item) {
  return item && "activeItem" in item && "region" in item && REGIONS[item.region] === true
}

function isCenterRegion(region) {
  return region === "centerBegin" || region === "center" || region === "centerEnd"
}

// The CenterSections item holding a center slot, if the host has one.
function centerSections(slot, root) {
  for (var item = slot.parent; item && item !== root; item = item.parent) {
    if ("besideRight" in item) return item
  }
  return null
}

// Center sections run on beside the right one move whenever the right
// section changes width.
function besideRight(slot, root) {
  var sections = centerSections(slot, root)
  return !!sections && sections.besideRight === true
}

function hostSlot(widget) {
  for (var item = widget.parent; item; item = item.parent) {
    if (isSlot(item) && item.activeItem === widget) return item
  }
  return null
}

function collectSlots(item, slots) {
  if (!item || item.visible !== true) return
  if (isSlot(item)) {
    slots.push(item)
    return // Do not descend into another widget's contents.
  }
  var children = item.children || []
  for (var i = 0; i < children.length; i++) collectSlots(children[i], slots)
}

// The room this widget may take before it would overlap another section.
// Every edge it is measured against stays put while the widget grows, and
// the widths of slots it pushes along are counted instead of their places,
// so the answer never follows the widget's own width.
function widthBudget(widget, contentItem, edgeMargin, collisionGap) {
  var ownSlot = hostSlot(widget)
  if (!ownSlot) return UNMEASURED
  if (!contentItem || contentItem.width <= 0) return 0

  var region = ownSlot.region
  // The tray's drawer shows its widgets only while it is open.
  if (region === "tray") return UNMEASURED

  var sections = isCenterRegion(region) ? centerSections(ownSlot, contentItem) : null
  // A center section on a host without Omarchy 4.5's layout.
  if (isCenterRegion(region) && !sections) return UNMEASURED
  // Beside the right section, all four sections grow toward the start of the
  // bar as one, as the right section alone does elsewhere.
  var chain = region === "right" || (!!sections && sections.besideRight === true)

  var slots = []
  collectSlots(contentItem, slots)
  if (slots.indexOf(ownSlot) === -1) return 0

  var own = ownSlot.mapToItem(contentItem, 0, 0)
  var leftEdge = edgeMargin
  var rightEdge = contentItem.width - edgeMargin
  var pushed = 0
  var chained = 0
  var before = 0
  var after = 0

  for (var i = 0; i < slots.length; i++) {
    var slot = slots[i]
    if (slot === ownSlot || slot.width <= 0 || slot.height <= 0) continue
    if (!slot.activeItem || slot.activeItem.visible !== true) continue

    var other = slot.region
    var point = slot.mapToItem(contentItem, 0, 0)
    var start = point.x
    var end = point.x + slot.width

    if (chain) {
      if (other === "right") pushed += slot.width
      else if (isCenterRegion(other) && besideRight(slot, contentItem)) chained += slot.width
      else leftEdge = Math.max(leftEdge, end)
    } else if (region === "left") {
      if (other === "left") pushed += slot.width
      else rightEdge = Math.min(rightEdge, start)
    } else if (region === "centerEnd") {
      // Growing to the right, it pushes the rest of centerEnd along.
      if (other === "centerEnd" && start >= own.x) pushed += slot.width
      else if (other === "right") rightEdge = Math.min(rightEdge, start)
    } else if (region === "centerBegin") {
      // Growing to the left, it pushes what comes before it in centerBegin.
      if (other === "centerBegin" && start < own.x) pushed += slot.width
      else if (other === "left") leftEdge = Math.max(leftEdge, end)
    } else {
      // The centered box grows both ways and pushes both sections beside it.
      if (other === "center") pushed += slot.width
      else if (other === "centerBegin") before += slot.width
      else if (other === "centerEnd") after += slot.width
      else if (other === "left") leftEdge = Math.max(leftEdge, end)
      else if (other === "right") rightEdge = Math.min(rightEdge, start)
    }
  }

  var available
  if (chain) {
    available = rightEdge - leftEdge - collisionGap - pushed
    // Beside the right section, the center sections keep a gap before it.
    if (region !== "right" || chained > 0) available -= chained + collisionGap
  } else if (region === "left") {
    available = rightEdge - leftEdge - collisionGap - pushed
  } else if (region === "centerEnd") {
    available = rightEdge - collisionGap - own.x - pushed
  } else if (region === "centerBegin") {
    available = own.x + ownSlot.width - leftEdge - collisionGap - pushed
  } else {
    // The box is centered in the sections, which do not change with it.
    var middle = sections.mapToItem(contentItem, sections.width / 2, 0).x
    var half = Math.min(middle - before - leftEdge - collisionGap,
      rightEdge - collisionGap - after - middle)
    // Less a pixel, since the host rounds the box to whole pixels.
    available = 2 * half - pushed - 1
  }
  return Math.max(0, Math.floor(available))
}
