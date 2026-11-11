// Measure only visual slots in this bar window. Third-party PluginBarApi
// objects no longer expose the host's moduleSlots or window helpers.
// Omarchy 4.5 splits the center into centerBegin, center and centerEnd.
var REGIONS = { left: true, centerBegin: true, center: true, centerEnd: true, right: true }

function isSlot(item) {
  return item && "activeItem" in item && "region" in item && REGIONS[item.region] === true
}

function isCenterRegion(region) {
  return region === "centerBegin" || region === "center" || region === "centerEnd"
}

// With a display notch, Omarchy 4.5 runs the center sections on just left of
// the right one (CenterSections with besideRight), so they move whenever the
// right section changes width.
function besideRight(slot, root) {
  for (var item = slot.parent; item && item !== root; item = item.parent) {
    if (item.besideRight === true) return true
  }
  return false
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

function widthBudget(widget, contentItem, edgeMargin, collisionGap) {
  var ownSlot = hostSlot(widget)
  if (!ownSlot || !contentItem || contentItem.width <= 0) return 0

  var region = ownSlot.region
  // Center modules can sit on either side of a separate center anchor;
  // they still need host cooperation to negotiate their available width.
  if (isCenterRegion(region)) return 100000

  var slots = []
  collectSlots(contentItem, slots)
  if (slots.indexOf(ownSlot) === -1) return 0

  var sameRegionWidth = 0
  var chainedWidth = 0
  var leftObstacle = edgeMargin
  var rightObstacle = contentItem.width - edgeMargin

  for (var i = 0; i < slots.length; i++) {
    var slot = slots[i]
    if (slot === ownSlot || slot.width <= 0 || slot.height <= 0) continue
    if (!slot.activeItem || slot.activeItem.visible !== true) continue

    if (slot.region === region) {
      sameRegionWidth += slot.width
      continue
    }

    // A position measured from such a slot would follow this widget's own
    // width. Count the room it takes instead.
    if (region === "right" && isCenterRegion(slot.region) && besideRight(slot, contentItem)) {
      chainedWidth += slot.width
      continue
    }

    var point = slot.mapToItem(contentItem, 0, 0)
    if (region === "right") {
      leftObstacle = Math.max(leftObstacle, point.x + slot.width)
    } else {
      rightObstacle = Math.min(rightObstacle, point.x)
    }
  }

  var available = region === "right"
    ? contentItem.width - edgeMargin - leftObstacle - collisionGap
    : rightObstacle - edgeMargin - collisionGap
  if (chainedWidth > 0) available -= chainedWidth + collisionGap
  return Math.max(0, Math.floor(available - sameRegionWidth))
}
