import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "shazam"

    property var popoutService: null

    readonly property bool listenOnClick: pluginData.listenOnClick !== false
    readonly property bool showTitleInBar: pluginData.showTitleInBar !== false
    readonly property int titleHoldSeconds: pluginData.titleHoldSeconds !== undefined ? pluginData.titleHoldSeconds : 20
    readonly property int pillMaxWidth: Math.max(60, pluginData.pillMaxWidth || 160)
    readonly property int historyShown: 6

    // The recognition itself lives in the daemon surface, so every bar shows the
    // same state and only one songrec process ever runs.
    readonly property var daemon: PluginService.pluginDaemonInstances[root.pluginId] || null

    readonly property string source: pluginData.source || "auto"
    readonly property string audioDevice: (pluginData.audioDevice || "").trim()
    readonly property string customActionLabel: (pluginData.customActionLabel || "").trim()
    readonly property string customActionCommand: (pluginData.customActionCommand || "").trim()

    readonly property var sourceValues: audioDevice ? ["auto", "mic", "device"] : ["auto", "mic"]
    readonly property var sourceLabels: audioDevice ? ["Output", "Mic", "Device"] : ["Output", "Mic"]
    readonly property int sourceIndex: Math.max(0, sourceValues.indexOf(source))

    readonly property var links: track && track.links ? track.links : []

    readonly property string shazamStatus: statusVar.value || "idle"
    readonly property var track: trackVar.value || null
    readonly property var history: historyVar.value || []
    readonly property string errorText: errorVar.value || ""
    readonly property bool listening: shazamStatus === "listening"

    property bool popoutOpen: false
    property bool showTitle: false

    PluginGlobalVar {
        id: statusVar
        varName: "status"
        defaultValue: "idle"
    }

    PluginGlobalVar {
        id: trackVar
        varName: "track"
        defaultValue: null
    }

    PluginGlobalVar {
        id: historyVar
        varName: "history"
        defaultValue: []
    }

    PluginGlobalVar {
        id: errorVar
        varName: "error"
        defaultValue: ""
    }

    onShazamStatusChanged: {
        if (shazamStatus === "listening") {
            showTitle = false;
            titleTimer.stop();
        } else if (shazamStatus === "found") {
            showTitle = true;
            if (titleHoldSeconds > 0) {
                titleTimer.restart();
            } else {
                titleTimer.stop();
            }
        }
    }

    Timer {
        id: titleTimer
        interval: Math.max(1, root.titleHoldSeconds) * 1000
        onTriggered: root.showTitle = false
    }

    function identify() {
        if (daemon) {
            daemon.identify();
        } else {
            Quickshell.execDetached(["dms", "ipc", "call", "shazam", "identify"]);
        }
    }

    function stopListening() {
        if (daemon) {
            daemon.stop();
        } else {
            Quickshell.execDetached(["dms", "ipc", "call", "shazam", "stop"]);
        }
    }

    function toggleIdentify() {
        if (listening) {
            stopListening();
        } else {
            identify();
        }
    }

    function clearHistory() {
        if (daemon) {
            daemon.clearHistory();
        }
    }

    function trackLabel(t) {
        if (!t) {
            return "";
        }
        return (t.artist ? t.artist + " — " : "") + t.title;
    }

    function copyTrack(t) {
        if (!t) {
            return;
        }
        Quickshell.execDetached(["dms", "cl", "copy", trackLabel(t)]);
        ToastService.showInfo("Copied " + trackLabel(t));
    }

    function openUrl(url) {
        if (!url) {
            return;
        }
        Quickshell.execDetached(["xdg-open", url]);
    }

    function setSource(index) {
        const value = sourceValues[index];
        if (!value || value === source) {
            return;
        }
        if (pluginService && pluginService.savePluginData) {
            pluginService.savePluginData(pluginId, "source", value);
        }
    }

    function trackDetails(t) {
        if (!t) {
            return "";
        }
        const lines = [trackLabel(t)];
        const release = [t.album, t.year].filter(v => !!v).join(" · ");
        if (release) {
            lines.push(release);
        }
        if (t.genre) {
            lines.push(t.genre);
        }
        if (t.isrc) {
            lines.push("ISRC " + t.isrc);
        }
        if (t.url) {
            lines.push(t.url);
        }
        return lines.join("\n");
    }

    function copyDetails(t) {
        if (!t) {
            return;
        }
        Quickshell.execDetached(["dms", "cl", "copy", trackDetails(t)]);
        ToastService.showInfo("Copied track details");
    }

    // The command is the user's own; the track fields are handed over as
    // positional arguments so nothing from Shazam is ever spliced into shell
    // source.
    function runCustomAction(t) {
        if (!t || !customActionCommand) {
            return;
        }
        const query = ((t.artist || "") + " " + (t.title || "")).trim();
        Quickshell.execDetached(["sh", "-c", customActionCommand, "dms-shazam", t.artist || "", t.title || "", t.album || "", t.url || "", query]);
        ToastService.showInfo((customActionLabel || "Action") + ": " + trackLabel(t));
    }

    function searchYouTube(t) {
        if (!t) {
            return;
        }
        openUrl("https://www.youtube.com/results?search_query=" + encodeURIComponent(t.artist + " " + t.title));
    }

    function timeAgo(ms) {
        if (!ms) {
            return "";
        }
        const diff = Math.max(0, Date.now() - ms);
        const mins = Math.floor(diff / 60000);
        if (mins < 1) {
            return "just now";
        }
        if (mins < 60) {
            return mins + "m ago";
        }
        const hours = Math.floor(mins / 60);
        if (hours < 24) {
            return hours + "h ago";
        }
        const days = Math.floor(hours / 24);
        if (days < 7) {
            return days + "d ago";
        }
        return Qt.formatDate(new Date(ms), "d MMM");
    }

    readonly property string pillIcon: {
        switch (shazamStatus) {
        case "listening":
            return "graphic_eq";
        case "found":
            return "music_note";
        case "notfound":
            return "music_off";
        case "error":
            return "error";
        default:
            return "graphic_eq";
        }
    }

    readonly property color pillColor: {
        if (shazamStatus === "error") {
            return Theme.error;
        }
        if (listening || (shazamStatus === "found" && showTitle)) {
            return Theme.primary;
        }
        return Theme.surfaceText;
    }

    readonly property string pillText: {
        if (!showTitleInBar) {
            return "";
        }
        if (listening) {
            return "Listening…";
        }
        if (showTitle && track) {
            return trackLabel(track);
        }
        return "";
    }

    // Left click opens the popout; with "identify on click" it also starts a
    // recognition, but only on the click that opens the popout (never the one
    // that closes it). popoutOpen is kept honest by the popout itself below.
    property var pillClick: function () {
        const opening = !root.popoutOpen;
        if (opening && root.listenOnClick && !root.listening) {
            root.identify();
        }
        // triggerPopout() delegates back to pillClickAction when it is set, so
        // it has to be cleared for the duration of the call.
        root.pillClickAction = null;
        root.triggerPopout();
        root.pillClickAction = root.pillClick;
    }

    Component.onCompleted: {
        pillClickAction = pillClick;
    }

    pillRightClickAction: function () {
        root.toggleIdentify();
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                id: hIcon

                property real pulse: 1

                anchors.verticalCenter: parent.verticalCenter
                name: root.pillIcon
                size: root.iconSize
                color: root.pillColor
                opacity: root.listening ? pulse : 1

                SequentialAnimation {
                    running: root.listening
                    loops: Animation.Infinite

                    NumberAnimation {
                        target: hIcon
                        property: "pulse"
                        from: 1
                        to: 0.35
                        duration: 550
                        easing.type: Easing.InOutQuad
                    }

                    NumberAnimation {
                        target: hIcon
                        property: "pulse"
                        from: 0.35
                        to: 1
                        duration: 550
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.pillText.length > 0
                implicitWidth: visible ? Math.min(hLabel.implicitWidth, root.pillMaxWidth) : 0
                implicitHeight: hLabel.implicitHeight
                clip: true

                StyledText {
                    id: hLabel
                    width: parent.width
                    text: root.pillText
                    // StyledText wraps by default, which would make the pill two
                    // rows tall in the bar.
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                    color: Theme.surfaceText
                }
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            id: vIcon

            property real pulse: 1

            name: root.pillIcon
            size: root.iconSize
            color: root.pillColor
            opacity: root.listening ? pulse : 1

            SequentialAnimation {
                running: root.listening
                loops: Animation.Infinite

                NumberAnimation {
                    target: vIcon
                    property: "pulse"
                    from: 1
                    to: 0.35
                    duration: 550
                    easing.type: Easing.InOutQuad
                }

                NumberAnimation {
                    target: vIcon
                    property: "pulse"
                    from: 0.35
                    to: 1
                    duration: 550
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }

    popoutWidth: 380

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Shazam"
            showCloseButton: true

            Connections {
                target: popout.parentPopout
                function onShouldBeVisibleChanged() {
                    root.popoutOpen = popout.parentPopout ? popout.parentPopout.shouldBeVisible : false;
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM

                Rectangle {
                    width: parent.width
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    implicitHeight: card.implicitHeight + Theme.spacingM * 2
                    height: implicitHeight

                    Column {
                        id: card

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingM
                            visible: root.listening

                            DankSpinner {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 28
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                StyledText {
                                    text: "Listening…"
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    text: "Sampling what is playing right now"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.spacingM
                            visible: !root.listening && root.track !== null

                            ClippingRectangle {
                                width: 64
                                height: 64
                                radius: Theme.cornerRadius
                                color: Theme.surfaceContainerHighest

                                CachingImage {
                                    id: cover
                                    anchors.fill: parent
                                    imagePath: root.track ? (root.track.cover || "") : ""
                                    maxCacheSize: 256
                                    fillMode: Image.PreserveAspectCrop
                                    animate: false
                                    visible: status === Image.Ready
                                }

                                DankIcon {
                                    anchors.centerIn: parent
                                    name: "album"
                                    size: Theme.iconSizeLarge
                                    color: Theme.withAlpha(Theme.outline, 0.8)
                                    visible: cover.status !== Image.Ready
                                }
                            }

                            Column {
                                width: parent.width - 64 - Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                StyledText {
                                    width: parent.width
                                    text: root.track ? root.track.title : ""
                                    elide: Text.ElideRight
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    width: parent.width
                                    text: root.track ? root.track.artist : ""
                                    elide: Text.ElideRight
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    width: parent.width
                                    text: root.track ? [root.track.album, root.track.year].filter(v => !!v).join(" · ") : ""
                                    visible: text.length > 0
                                    elide: Text.ElideRight
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.spacingM
                            visible: !root.listening && root.track === null

                            DankIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: root.shazamStatus === "error" ? "error" : (root.shazamStatus === "notfound" ? "music_off" : "graphic_eq")
                                size: Theme.iconSizeLarge
                                color: root.shazamStatus === "error" ? Theme.error : Theme.surfaceVariantText
                            }

                            Column {
                                width: parent.width - Theme.iconSizeLarge - Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                StyledText {
                                    width: parent.width
                                    text: root.shazamStatus === "error" ? "Something went wrong" : (root.shazamStatus === "notfound" ? "No match" : "Nothing identified yet")
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    width: parent.width
                                    text: root.shazamStatus === "error" ? root.errorText : (root.shazamStatus === "notfound" ? "Try again further into the track" : "Hit Identify while a song is playing")
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }
                        }
                    }
                }

                Flow {
                    width: parent.width
                    spacing: Theme.spacingXS
                    visible: root.links.length > 0 && !root.listening

                    Repeater {
                        model: root.links

                        Rectangle {
                            id: chip

                            required property var modelData

                            height: 28
                            width: chipLabel.implicitWidth + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: chipArea.containsMouse ? Theme.primaryHover : Theme.surfaceContainerHigh
                            border.width: 1
                            border.color: chipArea.containsMouse ? Theme.primary : Theme.outlineVariant

                            StyledText {
                                id: chipLabel
                                anchors.centerIn: parent
                                text: chip.modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                            }

                            MouseArea {
                                id: chipArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openUrl(chip.modelData.url)
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 40

                    DankButton {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.listening ? "Stop" : "Identify"
                        iconName: root.listening ? "stop" : "graphic_eq"
                        backgroundColor: root.listening ? Theme.surfaceContainerHighest : Theme.primary
                        textColor: root.listening ? Theme.surfaceText : Theme.primaryText
                        onClicked: root.toggleIdentify()
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        DankActionButton {
                            iconName: "content_copy"
                            tooltipText: "Copy artist and title"
                            visible: root.track !== null
                            onClicked: root.copyTrack(root.track)
                        }

                        DankActionButton {
                            iconName: "receipt_long"
                            tooltipText: "Copy title, album, year and ISRC"
                            visible: root.track !== null
                            onClicked: root.copyDetails(root.track)
                        }

                        DankActionButton {
                            iconName: "bolt"
                            tooltipText: root.customActionLabel || "Custom action"
                            visible: root.track !== null && root.customActionCommand.length > 0
                            onClicked: root.runCustomAction(root.track)
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 32

                    StyledText {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Listen to"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    DankButtonGroup {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        model: root.sourceLabels
                        currentIndex: root.sourceIndex
                        size: "small"
                        onSelectionChanged: index => root.setSource(index)
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS
                    visible: root.history.length > 0

                    Item {
                        width: parent.width
                        height: 28

                        StyledText {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Recent"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                        }

                        DankActionButton {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "delete_sweep"
                            buttonSize: 28
                            iconSize: Theme.iconSizeSmall
                            tooltipText: "Clear history"
                            onClicked: root.clearHistory()
                        }
                    }

                    Repeater {
                        model: root.history.slice(0, root.historyShown)

                        Rectangle {
                            id: histItem

                            required property var modelData

                            width: parent.width
                            height: 44
                            radius: Theme.cornerRadius
                            color: histArea.containsMouse ? Theme.surfaceContainerHigh : "transparent"

                            Row {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Theme.spacingS
                                anchors.rightMargin: Theme.spacingS
                                spacing: Theme.spacingS

                                ClippingRectangle {
                                    width: 32
                                    height: 32
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: Theme.cornerRadius / 2
                                    color: Theme.surfaceContainerHighest

                                    CachingImage {
                                        id: histCover
                                        anchors.fill: parent
                                        imagePath: histItem.modelData.cover || ""
                                        maxCacheSize: 128
                                        fillMode: Image.PreserveAspectCrop
                                        animate: false
                                        visible: status === Image.Ready
                                    }

                                    DankIcon {
                                        anchors.centerIn: parent
                                        name: "music_note"
                                        size: Theme.iconSizeSmall
                                        color: Theme.withAlpha(Theme.outline, 0.8)
                                        visible: histCover.status !== Image.Ready
                                    }
                                }

                                Column {
                                    width: parent.width - 32 - histTime.width - Theme.spacingS * 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1

                                    StyledText {
                                        width: parent.width
                                        text: histItem.modelData.title || ""
                                        elide: Text.ElideRight
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: Theme.surfaceText
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: histItem.modelData.artist || ""
                                        elide: Text.ElideRight
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }
                                }

                                StyledText {
                                    id: histTime
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.timeAgo(histItem.modelData.time)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }

                            MouseArea {
                                id: histArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        root.copyTrack(histItem.modelData);
                                        return;
                                    }
                                    root.openUrl(histItem.modelData.url || "");
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
