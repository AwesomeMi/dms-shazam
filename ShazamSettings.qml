import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "shazam"

    StyledText {
        width: parent.width
        text: "Shazam"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Identifies whatever is playing around you through SongRec. Left click the pill to open the panel, right click it to start or stop listening straight away."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SliderSetting {
        settingKey: "listenTimeout"
        label: "Listening timeout"
        description: "How long to keep sampling before giving up — SongRec sends a fingerprint every 10s, so a longer window means more attempts"
        defaultValue: 45
        minimum: 10
        maximum: 90
        unit: "s"
        leftIcon: "hourglass_empty"
    }

    ToggleSetting {
        settingKey: "listenOnClick"
        label: "Identify on click"
        description: "Start listening when the pill is clicked open, not just from the Identify button"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "notifyOnResult"
        label: "Notify on result"
        description: "Send a desktop notification when a song is recognized"
        defaultValue: true
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outline
        opacity: 0.3
    }

    ToggleSetting {
        settingKey: "showTitleInBar"
        label: "Show the track in the bar"
        description: "Display the recognized title next to the icon"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "titleHoldSeconds"
        label: "Keep the track visible"
        description: "Seconds before the pill collapses back to the icon (0 keeps it until the next run)"
        defaultValue: 20
        minimum: 0
        maximum: 120
        unit: "s"
        leftIcon: "timer"
    }

    SliderSetting {
        settingKey: "pillMaxWidth"
        label: "Maximum pill width"
        description: "Longer titles are elided at this width"
        defaultValue: 160
        minimum: 80
        maximum: 320
        unit: "px"
        leftIcon: "width"
    }

    SliderSetting {
        settingKey: "historySize"
        label: "History size"
        description: "How many recognized songs to remember"
        defaultValue: 20
        minimum: 5
        maximum: 50
        leftIcon: "history"
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outline
        opacity: 0.3
    }

    SelectionSetting {
        settingKey: "source"
        label: "Listen to"
        description: "Where the audio is sampled from"
        defaultValue: "auto"
        options: [
            {
                "label": "System output",
                "value": "auto"
            },
            {
                "label": "Microphone",
                "value": "mic"
            },
            {
                "label": "Specific device",
                "value": "device"
            }
        ]
    }

    StyledText {
        width: parent.width
        text: "System output follows whichever output is default at the time, by recording its monitor source. Microphone uses the default input."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "audioDevice"
        label: "Audio device"
        description: "Used with 'Specific device'. Run 'songrec recognize -l' for the names; a '.monitor' one is an output, the rest are inputs."
        placeholder: "alsa_output.….monitor"
    }

    StyledText {
        width: parent.width
        text: "Bind a key to 'dms ipc call shazam identify' to identify a song without touching the bar."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outline
        opacity: 0.3
    }

    StyledText {
        width: parent.width
        text: "Custom action"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Adds a button to the panel that runs your own command for the recognized track. The track is passed as arguments, not spliced into the command: $1 artist, $2 title, $3 album, $4 Shazam URL, $5 \"artist title\". Leave the command empty to hide the button."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "customActionLabel"
        label: "Button tooltip"
        description: "What the button says when you hover it"
        placeholder: "Add to wishlist"
    }

    StringSetting {
        settingKey: "customActionCommand"
        label: "Command"
        description: "Runs through sh. Example: printf '%s\\n' \"$5\" >> ~/Music/wishlist.txt"
        placeholder: "printf '%s\\n' \"$5\" >> ~/Music/wishlist.txt"
    }
}
