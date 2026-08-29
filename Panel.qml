import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "openlogi-omarchy"
  ipcTarget: "openlogi-omarchy"
  manageIpc: false

  property string focusSection: "header"
  property int itemIndex: 0
  property int actionIndex: 0
  property bool cursorActive: false
  property int phraseIndex: 0

  readonly property var activePhrases: [
    "Remapping active",
    "HID++ connected",
    "Agent listening",
    "Profiles loaded",
    "Devices tracked",
    "Input hooks live"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && openlogi.installed
  readonly property bool rotatingPhrases: openlogi.agentActive && openlogi.items.length > 0
  readonly property color iconColor: openlogi.agentActive ? foreground : dim
  readonly property string toggleHint: openlogi.agentActive ? "Stop OpenLogi agent" : "Start OpenLogi agent"
  readonly property color barIconColor: openlogi.agentActive && openlogi.installed ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property string heroTitleText: Model.heroTitle(openlogi.installed, openlogi.agentActive, openlogi.primaryDevice)
  readonly property string heroMetaText: heroMetaLine()
  readonly property var actionRows: [
    { id: "configure", title: "Configure…", detail: "Open OpenLogi to remap buttons and DPI", icon: "󰘖", enabled: openlogi.desktopInstalled },
    { id: "settings", title: "Settings…", detail: "Open OpenLogi (Settings is inside the app on Linux)", icon: "󰒓", enabled: openlogi.desktopInstalled },
    { id: "restart", title: "Restart agent", detail: "Recover if devices stop responding", icon: "󰑐", enabled: openlogi.installed }
  ]

  function heroMetaLine() {
    var meta = Model.heroMeta(
      openlogi.installed,
      openlogi.agentActive,
      openlogi.socketPresent,
      openlogi.statusText,
      openlogi.items,
      heroPhraseText
    )
    var primary = openlogi.primaryDevice
    if (primary && primary.battery && openlogi.agentActive) {
      var label = Model.batteryLabel(primary.battery)
      if (label !== "—") return meta + " · " + label
    }
    return meta
  }

  function ensureCursor() {
    if (!openlogi.installed) {
      focusSection = "header"
      itemIndex = 0
      actionIndex = 0
      return
    }
    if (focusSection === "devices" && openlogi.items.length === 0) focusSection = "actions"
    if (focusSection === "actions") {
      if (actionIndex >= actionRows.length) actionIndex = Math.max(0, actionRows.length - 1)
      if (actionIndex < 0) actionIndex = 0
      return
    }
    if (openlogi.items.length === 0 && focusSection === "devices") {
      focusSection = "actions"
      actionIndex = 0
      return
    }
    if (focusSection !== "devices" && focusSection !== "header" && focusSection !== "actions") focusSection = "header"
    if (itemIndex >= openlogi.items.length) itemIndex = Math.max(0, openlogi.items.length - 1)
    if (itemIndex < 0) itemIndex = 0
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
  }

  function setItemCursor(index) {
    cursorActive = true
    focusSection = "devices"
    itemIndex = index
  }

  function setActionCursor(index) {
    cursorActive = true
    focusSection = "actions"
    actionIndex = index
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    if (focusSection === "header") {
      if (dy > 0) {
        if (openlogi.items.length > 0) {
          focusSection = "devices"
          itemIndex = 0
        } else {
          focusSection = "actions"
          actionIndex = 0
        }
      }
      return
    }
    if (focusSection === "devices") {
      if (dy < 0 && itemIndex === 0) {
        setHeaderCursor()
        return
      }
      if (dy > 0 && itemIndex >= openlogi.items.length - 1) {
        focusSection = "actions"
        actionIndex = 0
        return
      }
      itemIndex = Math.max(0, Math.min(openlogi.items.length - 1, itemIndex + dy))
      return
    }
    if (focusSection === "actions") {
      if (dy < 0) {
        if (openlogi.items.length > 0) {
          focusSection = "devices"
          itemIndex = openlogi.items.length - 1
        } else {
          setHeaderCursor()
        }
        return
      }
      actionIndex = Math.max(0, Math.min(actionRows.length - 1, actionIndex + dy))
    }
  }

  function runAction(id) {
    if (id === "configure") openlogi.openConfigure()
    else if (id === "settings") openlogi.openSettings()
    else if (id === "restart") openlogi.restartAgent()
  }

  function activateCursor() {
    if (focusSection === "header") openlogi.toggleAgent()
    else if (focusSection === "devices") openlogi.openConfigure()
    else if (focusSection === "actions") {
      var row = actionRows[actionIndex]
      if (row && row.enabled) runAction(row.id)
    }
  }

  function toggleRunning() {
    openlogi.toggleAgent()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
    openlogi.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Timer {
    id: phraseTimer
    interval: 3200
    repeat: true
    running: root.rotatingPhrases
    onTriggered: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
  }

  Service {
    id: openlogi
    settings: root.settings
  }

  Connections {
    target: openlogi
    function onItemsChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { openlogi.refresh(); return "ok" }
    function configure(): string { openlogi.openConfigure(); return "ok" }
    function status(): string { return openlogi.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        OpenLogiIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
          crossed: !openlogi.installed || !openlogi.agentActive
          warning: openlogi.lowBattery
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) openlogi.refresh()
      else if (buttonCode === Qt.MiddleButton) openlogi.openConfigure()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") openlogi.refresh()
        else if (t === "c" || t === "C") openlogi.openConfigure()
        else if (t === "s" || t === "S") openlogi.openSettings()
        else if (t === "a" || t === "A") openlogi.toggleAgent()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: root.heroTitleText
              meta: root.heroMetaText
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: openlogi.agentActive ? 1.0 : 0.5
              iconComponent: Component {
                OpenLogiIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  crossed: !openlogi.agentActive
                  warning: openlogi.lowBattery
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: openlogi.installed
                  checked: openlogi.agentActive
                  busy: openlogi.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: openlogi.toggleAgent()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: openlogi.actionStatus !== "" || openlogi.lastError !== ""
            width: parent.width
            text: openlogi.actionStatus !== "" ? openlogi.actionStatus : openlogi.lastError
            color: openlogi.lastError !== "" && openlogi.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: openlogi.healthIssues.length > 0
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: openlogi.healthIssues
              delegate: Text {
                required property var modelData
                width: parent.width
                text: "⚠ " + String(modelData || "")
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }
          }

          CursorSurface {
            visible: !openlogi.installed
            width: parent.width
            implicitHeight: missingText.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground

            Text {
              id: missingText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              text: "Install OpenLogi, then enable the background agent. Configure devices in the OpenLogi app."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator {
            visible: openlogi.installed
            foreground: root.foreground
          }

          Column {
            visible: openlogi.installed
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "DEVICES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: openlogi.items.length === 0
              width: parent.width
              text: "No Logitech devices detected. Plug in a receiver or pair over Bluetooth, then configure in OpenLogi."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: openlogi.items
              delegate: DeviceRow {
                width: parent.width
                item: modelData
                rowIndex: index
              }
            }
          }

          PanelSeparator {
            visible: openlogi.installed
            foreground: root.foreground
          }

          Column {
            visible: openlogi.installed
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.actionRows
              delegate: ActionRow {
                width: parent.width
                row: modelData
                rowIndex: index
              }
            }
          }

          Text {
            visible: openlogi.installed && openlogi.version !== ""
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: openlogi.version
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  component DeviceRow: CursorSurface {
    id: deviceRow
    property var item: null
    property int rowIndex: 0
    readonly property string itemName: item ? String(item.name || "Unknown device") : "Unknown device"
    readonly property string itemKind: item ? String(item.kind || "device") : "device"
    readonly property bool online: item ? item.online !== false : false
    readonly property string batteryText: Model.batteryLabel(item ? item.battery : null)

    hasCursor: root.cursorActive && root.focusSection === "devices" && root.itemIndex === rowIndex
    foreground: root.foreground
    implicitHeight: row.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: deviceMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setItemCursor(deviceRow.rowIndex)
      onClicked: openlogi.openConfigure()
    }

    RowLayout {
      id: row
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: deviceRow.online ? "●" : "○"
        color: deviceRow.online ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        text: Model.deviceGlyph(deviceRow.itemKind)
        color: deviceRow.online ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: deviceRow.itemName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: Model.kindLabel(deviceRow.itemKind)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        visible: deviceRow.batteryText !== "—"
        text: deviceRow.batteryText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.alignment: Qt.AlignVCenter
      }
    }

    PanelToolTip {
      visible: deviceMouse.containsMouse
      text: "Configure in OpenLogi"
      fontFamily: root.fontFamily
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    property var row: null
    property int rowIndex: 0
    readonly property bool rowEnabled: row ? row.enabled === true && !openlogi.busy : false

    hasCursor: root.cursorActive && root.focusSection === "actions" && root.actionIndex === rowIndex
    foreground: root.foreground
    implicitHeight: content.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: actionRow.rowEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: actionRow.rowEnabled
      onEntered: root.setActionCursor(actionRow.rowIndex)
      onClicked: root.runAction(actionRow.row.id)
    }

    RowLayout {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)
      opacity: actionRow.rowEnabled ? 1.0 : 0.45

      Text {
        text: actionRow.row ? String(actionRow.row.icon || "󰌾") : "󰌾"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: actionRow.row ? String(actionRow.row.title || "") : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: actionRow.row ? String(actionRow.row.detail || "") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          wrapMode: Text.Wrap
        }
      }
    }
  }
}
