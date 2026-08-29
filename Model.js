function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return defaultStatus()
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return defaultStatus()
    parsed.receivers = Array.isArray(parsed.receivers) ? parsed.receivers : []
    parsed.devices = Array.isArray(parsed.devices) ? parsed.devices : []
    parsed.cameras = Array.isArray(parsed.cameras) ? parsed.cameras : []
    return parsed
  } catch (e) {
    var failed = defaultStatus()
    failed.ok = false
    failed.lastError = "Failed to parse OpenLogi status"
    return failed
  }
}

function defaultStatus() {
  return {
    ok: true,
    installed: false,
    desktopInstalled: false,
    agentInstalled: false,
    version: "",
    agentActive: false,
    agentEnabled: false,
    socketPresent: false,
    scanFailed: false,
    statusText: "Unavailable",
    receivers: [],
    devices: [],
    cameras: [],
    lastError: ""
  }
}

function allItems(devices, cameras) {
  var rows = []
  var i
  for (i = 0; i < (devices || []).length; i++) rows.push(devices[i])
  for (i = 0; i < (cameras || []).length; i++) rows.push(cameras[i])
  return rows
}

function kindRank(kind) {
  var value = String(kind || "").toLowerCase()
  if (value.indexOf("mouse") >= 0 || value.indexOf("trackball") >= 0) return 0
  if (value.indexOf("keyboard") >= 0) return 1
  if (value.indexOf("camera") >= 0) return 2
  return 3
}

function primaryDevice(items) {
  if (!items || items.length === 0) return null
  var best = null
  var bestRank = 99
  var i
  for (i = 0; i < items.length; i++) {
    var item = items[i]
    if (!item) continue
    var rank = kindRank(item.kind)
    var online = item.online !== false
    var score = rank + (online ? 0 : 10)
    if (!best || score < bestRank) {
      best = item
      bestRank = score
    }
  }
  return best
}

function hasLowBattery(items, threshold) {
  var limit = Number(threshold || 20)
  if (!isFinite(limit)) limit = 20
  var i
  for (i = 0; i < (items || []).length; i++) {
    var battery = items[i] && items[i].battery
    if (!battery) continue
    var percent = Number(battery.percent)
    if (isFinite(percent) && percent > 0 && percent <= limit) return true
  }
  return false
}

function heroTitle(installed, agentActive, primary) {
  if (!installed) return "OpenLogi"
  if (!agentActive) return "OpenLogi"
  if (primary && primary.name) return String(primary.name)
  return "OpenLogi"
}

function heroMeta(installed, agentActive, socketPresent, statusText, items, rotatingPhrase) {
  if (!installed) return "Package not installed"
  if (!agentActive) return "Agent stopped — remapping is off"
  if (agentActive && !socketPresent) return "Agent is starting…"
  if ((items || []).length > 0) return rotatingPhrase
  return String(statusText || "No devices connected")
}

function healthIssues(installed, agentActive, socketPresent, scanFailed, desktopInstalled) {
  var issues = []
  if (!installed) {
    issues.push("Install the openlogi package to use Logitech devices.")
    return issues
  }
  if (!desktopInstalled) issues.push("openlogi-desktop is missing from PATH.")
  if (!agentActive) issues.push("Background agent is stopped.")
  else if (!socketPresent) issues.push("Agent socket is not ready yet.")
  if (scanFailed) issues.push("Device scan failed — check agent logs.")
  return issues
}

function deviceGlyph(kind) {
  var value = String(kind || "").toLowerCase()
  if (value.indexOf("mouse") >= 0 || value.indexOf("trackball") >= 0) return "󰍽"
  if (value.indexOf("keyboard") >= 0) return "󰌌"
  if (value.indexOf("camera") >= 0) return "󰄀"
  if (value.indexOf("light") >= 0) return "󰌵"
  return "󰋊"
}

function batteryGlyph(battery) {
  if (!battery || battery.percent === undefined || battery.percent === null) return ""
  var percent = Number(battery.percent)
  if (!isFinite(percent)) return ""
  if (percent >= 90) return "󰁹"
  if (percent >= 70) return "󰂀"
  if (percent >= 50) return "󰁾"
  if (percent >= 30) return "󰁼"
  if (percent >= 15) return "󰁺"
  return "󰁻"
}

function batteryLabel(battery) {
  if (!battery || battery.percent === undefined || battery.percent === null) return "—"
  return String(battery.percent) + "%"
}

function kindLabel(kind) {
  var value = String(kind || "device").toLowerCase()
  if (value.indexOf("mouse") >= 0) return "Mouse"
  if (value.indexOf("trackball") >= 0) return "Trackball"
  if (value.indexOf("keyboard") >= 0) return "Keyboard"
  if (value.indexOf("camera") >= 0) return "Camera"
  if (value.indexOf("light") >= 0) return "Light"
  return value.charAt(0).toUpperCase() + value.slice(1)
}
