import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool desktopInstalled: false
  property bool agentInstalled: false
  property string version: ""
  property bool agentActive: false
  property bool agentEnabled: false
  property bool socketPresent: false
  property bool scanFailed: false
  property bool lowBattery: false
  property string statusText: "Checking…"
  property var primaryDevice: null
  property var receivers: []
  property var devices: []
  property var cameras: []
  property string actionStatus: ""
  property string lastError: ""
  property bool refreshing: false
  property string _statusOutput: ""
  property string _statusError: ""
  property string _controlOutput: ""
  property string _controlError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property bool busy: statusProcess.running || controlProcess.running
  readonly property var items: Model.allItems(devices, cameras)
  readonly property var healthIssues: Model.healthIssues(installed, agentActive, socketPresent, scanFailed, desktopInstalled)
  readonly property string helperPath: fileUrlToPath(Qt.resolvedUrl("status.py"))

  function fileUrlToPath(url) {
    var s = String(url || "")
    if (s.indexOf("file://") === 0)
      s = decodeURIComponent(s.substring(7))
    return s
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function refresh() {
    if (statusProcess.running || helperPath === "") return
    refreshing = true
    statusProcess.command = ["python3", helperPath]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      lastError = parsed.lastError || "Failed to read OpenLogi status"
      return
    }
    installed = parsed.installed === true
    desktopInstalled = parsed.desktopInstalled === true
    agentInstalled = parsed.agentInstalled === true
    version = String(parsed.version || "")
    agentActive = parsed.agentActive === true
    agentEnabled = parsed.agentEnabled === true
    socketPresent = parsed.socketPresent === true
    scanFailed = parsed.scanFailed === true
    lowBattery = parsed.lowBattery === true
    statusText = String(parsed.statusText || "Unavailable")
    primaryDevice = parsed.primaryDevice || null
    receivers = parsed.receivers || []
    devices = parsed.devices || []
    cameras = parsed.cameras || []
    lastError = ""
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function launchDesktop() {
    if (!desktopInstalled) return
    Quickshell.execDetached(["uwsm-app", "--", "/usr/bin/openlogi-desktop"])
  }

  function openConfigure() {
    launchDesktop()
  }

  function openSettings() {
    launchDesktop()
  }

  function enableAgent() {
    runControl(["systemctl", "--user", "enable", "--now", "openlogi-agent.service"], "Starting OpenLogi agent…")
  }

  function restartAgent() {
    runControl(["systemctl", "--user", "restart", "openlogi-agent.service"], "Restarting OpenLogi agent…")
  }

  function toggleAgent() {
    if (agentActive) runControl(["systemctl", "--user", "stop", "openlogi-agent.service"], "Stopping OpenLogi agent…")
    else enableAgent()
  }

  function runControl(command, label) {
    if (!installed || controlProcess.running) return
    actionStatus = label || ""
    controlProcess.command = command
    controlProcess.running = true
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: root.helperPath !== ""
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 800
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.applyStatus(stdout)
      else root.lastError = root.elideStatus(stderr || stdout || "Could not read OpenLogi status")
    }
  }

  Process {
    id: controlProcess
    running: false
    command: []
    stdout: StdioCollector { id: controlStdout; waitForEnd: true; onStreamFinished: root._controlOutput = text }
    stderr: StdioCollector { id: controlStderr; waitForEnd: true; onStreamFinished: root._controlError = text }
    onExited: function(exitCode) {
      var stdout = String(controlStdout.text || root._controlOutput || "")
      var stderr = String(controlStderr.text || root._controlError || "")
      if (exitCode !== 0) {
        root.lastError = root.elideStatus(stderr || stdout || "OpenLogi command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        if (root.actionStatus !== "") actionStatusTimer.restart()
      }
      delayedRefresh.restart()
    }
  }
}
