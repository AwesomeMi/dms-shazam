import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

// Single instance for the whole shell: owns the songrec process so that a
// multi-monitor setup does not start one recognition per bar, and keeps the
// result available to every bar widget through plugin global vars.
PluginComponent {
    id: root

    readonly property int listenTimeout: Math.max(10, pluginData.listenTimeout || 45)
    // auto | mic | device
    readonly property string source: pluginData.source || "auto"
    readonly property string audioDevice: (pluginData.audioDevice || "").trim()
    readonly property bool notifyOnResult: pluginData.notifyOnResult !== false
    readonly property int historySize: Math.max(1, pluginData.historySize || 20)

    // idle | listening | found | notfound | error
    property string status: "idle"
    property var track: null
    property var history: []
    property string errorText: ""

    property string _stdout: ""
    property string _stderr: ""
    property bool _cancelled: false

    onStatusChanged: publishState()
    onTrackChanged: publishState()
    onHistoryChanged: publishState()
    onErrorTextChanged: publishState()

    Component.onCompleted: {
        const stored = pluginService && pluginService.loadPluginState ? pluginService.loadPluginState(pluginId, "history", []) : [];
        history = Array.isArray(stored) ? stored : [];
        publishState();
    }

    Component.onDestruction: {
        if (recognizeProc.running) {
            recognizeProc.running = false;
        }
    }

    function publishState() {
        if (!pluginId) {
            return;
        }
        PluginService.setGlobalVar(pluginId, "status", status);
        PluginService.setGlobalVar(pluginId, "track", track);
        PluginService.setGlobalVar(pluginId, "history", history);
        PluginService.setGlobalVar(pluginId, "error", errorText);
    }

    function identify() {
        if (recognizeProc.running) {
            return "already listening";
        }
        _stdout = "";
        _stderr = "";
        _cancelled = false;
        errorText = "";
        track = null;
        status = "listening";
        recognizeProc.command = buildCommand();
        recognizeProc.running = true;
        return "listening";
    }

    function stop() {
        if (!recognizeProc.running) {
            return;
        }
        _cancelled = true;
        recognizeProc.running = false;
    }

    function toggle() {
        if (recognizeProc.running) {
            stop();
            return "stopped";
        }
        return identify();
    }

    // SongRec's own live capture comes back empty from a PipeWire monitor
    // source — it samples for minutes without ever matching audio that it
    // recognizes instantly from a file. So the sampling is done here instead:
    // record a chunk with parecord, hand the file to songrec, repeat until the
    // budget runs out.
    readonly property int sampleSeconds: 13
    readonly property int sampleRounds: Math.max(1, Math.floor(listenTimeout / (sampleSeconds + 4)))

    readonly property string _script: 'mode="$1"; dev="$2"; rounds="$3"; secs="$4"
if [ "$mode" = auto ]; then
  sink="$(pactl get-default-sink 2>/dev/null)"
  if [ -n "$sink" ]; then dev="$sink.monitor"; else dev=""; fi
elif [ "$mode" = mic ]; then
  dev=""
fi

tmp="$(mktemp -t dms-shazam-XXXXXXXX.wav)" || exit 1
rec=""
cleanup() { [ -n "$rec" ] && kill "$rec" 2>/dev/null; rm -f "$tmp"; }
trap \'cleanup; exit 143\' TERM INT

i=0
while [ "$i" -lt "$rounds" ]; do
  i=$((i+1))
  if [ -n "$dev" ]; then
    timeout "$secs" parecord --device="$dev" --file-format=wav --rate=44100 --channels=2 "$tmp" &
  else
    timeout "$secs" parecord --file-format=wav --rate=44100 --channels=2 "$tmp" &
  fi
  rec=$!
  wait "$rec"
  rec=""
  out="$(songrec recognize --json "$tmp" 2>/dev/null)"
  case "$out" in
    *\'"track"\'*) printf "%s\\n" "$out"; cleanup; exit 0 ;;
  esac
done

cleanup
exit 0'

    function buildCommand() {
        const mode = (source === "device" && audioDevice) ? "device" : (source === "mic" ? "mic" : "auto");
        const hardLimit = listenTimeout + sampleSeconds + 10;
        return ["timeout", "-k", "2", String(hardLimit), "sh", "-c", _script, "dms-shazam", mode, audioDevice, String(sampleRounds), String(sampleSeconds)];
    }

    // Shazam ships deep links for the streaming services in the response, so
    // the only thing to do is unwrap them: app URIs get a web equivalent, and
    // the Apple link hides inside an android intent:// wrapper.
    function _links(t) {
        const out = [];
        if (t.url) {
            out.push({
                "id": "shazam",
                "label": "Shazam",
                "url": t.url
            });
        }

        const hub = t.hub || {};
        const providers = Array.isArray(hub.providers) ? hub.providers : [];
        for (let i = 0; i < providers.length; i++) {
            const p = providers[i];
            const actions = Array.isArray(p.actions) ? p.actions : [];
            const uri = actions.length ? (actions[0].uri || "") : "";
            if (!uri) {
                continue;
            }
            if (p.type === "SPOTIFY") {
                out.push({
                    "id": "spotify",
                    "label": "Spotify",
                    "url": uri.indexOf("spotify:search:") === 0 ? "https://open.spotify.com/search/" + uri.substring(15) : uri
                });
            } else if (p.type === "YOUTUBEMUSIC" && uri.indexOf("http") === 0) {
                out.push({
                    "id": "ytmusic",
                    "label": "YT Music",
                    "url": uri
                });
            } else if (p.type === "DEEZER") {
                out.push({
                    "id": "deezer",
                    "label": "Deezer",
                    "url": uri.indexOf("http") === 0 ? uri : "https://www.deezer.com/search/" + encodeURIComponent(((t.subtitle || "") + " " + (t.title || "")).trim())
                });
            }
        }

        const apple = _appleUrl(hub);
        if (apple) {
            out.push({
                "id": "applemusic",
                "label": "Apple Music",
                "url": apple
            });
        }

        if (t.title) {
            out.push({
                "id": "youtube",
                "label": "YouTube",
                "url": "https://www.youtube.com/results?search_query=" + encodeURIComponent(((t.subtitle || "") + " " + t.title).trim())
            });
        }
        return out;
    }

    function _appleUrl(hub) {
        const options = Array.isArray(hub.options) ? hub.options : [];
        for (let i = 0; i < options.length; i++) {
            const actions = Array.isArray(options[i].actions) ? options[i].actions : [];
            for (let j = 0; j < actions.length; j++) {
                const uri = actions[j].uri || "";
                if (uri.indexOf("intent://music.apple.com") !== 0) {
                    continue;
                }
                const bare = uri.substring("intent://".length).split("#Intent")[0];
                const parts = bare.split("?");
                const query = (parts[1] || "").split("&").filter(kv => kv.indexOf("i=") === 0);
                // Everything else in the query is Shazam's referral tagging.
                return "https://" + parts[0] + (query.length ? "?" + query[0] : "");
            }
        }
        return "";
    }

    function _extract(obj) {
        const t = obj && obj.track ? obj.track : null;
        if (!t || !t.title) {
            return null;
        }

        let album = "";
        let year = "";
        const sections = Array.isArray(t.sections) ? t.sections : [];
        for (let i = 0; i < sections.length; i++) {
            const meta = Array.isArray(sections[i].metadata) ? sections[i].metadata : [];
            for (let j = 0; j < meta.length; j++) {
                if (meta[j].title === "Album") {
                    album = meta[j].text || "";
                } else if (meta[j].title === "Released") {
                    year = meta[j].text || "";
                }
            }
        }

        const images = t.images || {};
        return {
            "links": _links(t),
            "isrc": t.isrc || "",
            "title": t.title || "",
            "artist": t.subtitle || "",
            "album": album,
            "year": year,
            "genre": (t.genres && t.genres.primary) || "",
            "cover": images.coverarthq || images.coverart || "",
            "url": t.url || (t.share && t.share.href) || "",
            "key": t.key || "",
            "time": Date.now()
        };
    }

    function parseTrack(text) {
        const raw = (text || "").trim();
        if (!raw) {
            return null;
        }
        try {
            const single = _extract(JSON.parse(raw));
            if (single) {
                return single;
            }
        } catch (e) {}

        // Fall back to the last line that parses on its own, in case songrec
        // printed more than one response before exiting.
        const lines = raw.split("\n");
        for (let i = lines.length - 1; i >= 0; i--) {
            const line = lines[i].trim();
            if (!line.startsWith("{")) {
                continue;
            }
            try {
                const parsed = _extract(JSON.parse(line));
                if (parsed) {
                    return parsed;
                }
            } catch (e2) {}
        }
        return null;
    }

    function addToHistory(entry) {
        const next = history.slice();
        if (next.length > 0 && next[0].key && next[0].key === entry.key) {
            next.shift();
        }
        next.unshift(entry);
        history = next.slice(0, historySize);
        if (pluginService && pluginService.savePluginState) {
            pluginService.savePluginState(pluginId, "history", history);
        }
    }

    function clearHistory() {
        history = [];
        if (pluginService && pluginService.savePluginState) {
            pluginService.savePluginState(pluginId, "history", []);
        }
    }

    function _notify(summary, body, icon) {
        Quickshell.execDetached(["dms", "notify", summary, body, "--icon", icon, "--app", "Shazam"]);
    }

    function _handleExit(exitCode) {
        if (_cancelled) {
            _cancelled = false;
            status = "idle";
            return;
        }

        const found = parseTrack(_stdout);
        if (found) {
            track = found;
            status = "found";
            addToHistory(found);
            if (notifyOnResult) {
                _notify(found.title, found.artist + (found.album ? " · " + found.album : ""), "music_note");
            }
            return;
        }

        // songrec only prints when it matched something, so output we failed to
        // read is a parser problem, not a miss — say so instead of quietly
        // reporting "no match".
        if ((_stdout || "").trim()) {
            console.warn("Shazam: could not parse songrec output:", _stdout.substring(0, 800));
            errorText = "Could not read the Shazam response";
            status = "error";
            ToastService.showError("Shazam", errorText);
            return;
        }

        // songrec bails out with a zero exit code on a bad device or a missing
        // one, so the reason has to be read off stderr.
        const logged = (_stderr || "").trim();
        if (logged.indexOf("Exiting:") !== -1) {
            const lines = logged.split("\n").filter(l => l.indexOf("Exiting:") !== -1);
            errorText = lines[lines.length - 1].trim();
            status = "error";
            ToastService.showError("Shazam", errorText);
            return;
        }

        // 124: timeout fired. 0: songrec gave up without printing a match.
        if (exitCode === 0 || exitCode === 124 || exitCode === 137 || exitCode === 143) {
            status = "notfound";
            if (notifyOnResult) {
                _notify("Shazam", "No match — try again further into the track", "music_off");
            }
            return;
        }

        errorText = (_stderr || "").trim() || ("songrec exited with code " + exitCode);
        status = "error";
        ToastService.showError("Shazam", errorText);
    }

    Process {
        id: recognizeProc

        running: false

        stdout: StdioCollector {
            onStreamFinished: root._stdout = text
        }

        stderr: StdioCollector {
            onStreamFinished: root._stderr = text
        }

        onExited: exitCode => root._handleExit(exitCode)
    }

    IpcHandler {
        target: "shazam"

        function identify(): string {
            return root.identify();
        }

        function stop(): string {
            root.stop();
            return "stopped";
        }

        function toggle(): string {
            return root.toggle();
        }

        function state(): string {
            return root.status;
        }

        function last(): string {
            if (!root.track) {
                return "nothing recognized yet";
            }
            return root.track.artist + " - " + root.track.title;
        }
    }
}
