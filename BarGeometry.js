// Measure only visual slots in this bar window. Third-party PluginBarApi
// objects no longer expose the host's moduleSlots or window helpers.
function isSlot(item) {
  return item && "activeItem" in item && "region" in item
    && (item.region === "left" || item.region === "center" || item.region === "right")
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
  if (region === "center") return 100000

  var slots = []
  collectSlots(contentItem, slots)
  if (slots.indexOf(ownSlot) === -1) return 0

  var sameRegionWidth = 0
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
  return Math.max(0, Math.floor(available - sameRegionWidth))
}
