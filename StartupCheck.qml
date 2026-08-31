import QtQuick
import qs.Common

QtObject {
    function check(done) {
        Proc.runCommand("shazam.depCheck", ["sh", "-c", "for c in songrec parecord pactl; do command -v $c >/dev/null || { echo $c; exit 1; }; done"], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            const missing = (stdout || "").trim() || "songrec";
            done({
                "title": missing + " is required",
                "details": "'" + missing + "' is not installed or not on your PATH.\n\nArch Linux:  sudo pacman -S songrec libpulse\n\nThen re-enable this plugin."
            });
        });
    }
}
