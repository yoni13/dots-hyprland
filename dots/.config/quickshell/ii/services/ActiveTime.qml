pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    readonly property int idleTimeoutSeconds: 5 * 60
    readonly property int breakReminderSeconds: 60 * 60

    property bool initialized: false
    property bool suspended: false
    property real activeSince: 0
    property real nowMs: Date.now()
    property bool reminderSent: false

    readonly property bool active: initialized && !suspended && !idleMonitor.isIdle && activeSince > 0
    readonly property int activeSeconds: active ? Math.max(0, Math.floor((nowMs - activeSince) / 1000)) : 0
    readonly property bool needsBreak: activeSeconds >= breakReminderSeconds
    readonly property string formatted: {
        if (!active)
            return Translation.tr("Resting");
        if (activeSeconds < 60)
            return Translation.tr("<1m");

        const hours = Math.floor(activeSeconds / 3600);
        const minutes = Math.floor((activeSeconds % 3600) / 60);
        return hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`;
    }
    readonly property string formattedLong: {
        if (!active)
            return Translation.tr("Resting");

        const hours = Math.floor(activeSeconds / 3600);
        const minutes = Math.floor((activeSeconds % 3600) / 60);
        if (hours === 0)
            return Translation.tr("%1 minutes").arg(minutes);
        if (minutes === 0)
            return Translation.tr("%1 hours").arg(hours);
        return Translation.tr("%1 hours, %2 minutes").arg(hours).arg(minutes);
    }

    function load(): void {}

    function persist(): void {
        if (!Persistent.ready)
            return;
        Persistent.states.activeTime.activeSince = root.activeSince;
        Persistent.states.activeTime.reminderSent = root.reminderSent;
    }

    function startSession(): void {
        if (!initialized || suspended || idleMonitor.isIdle)
            return;
        nowMs = Date.now();
        activeSince = nowMs;
        reminderSent = false;
        persist();
    }

    function endSession(): void {
        activeSince = 0;
        reminderSent = false;
        nowMs = Date.now();
        persist();
    }

    function initialize(): void {
        if (initialized || !Persistent.ready)
            return;

        initialized = true;
        nowMs = Date.now();

        const storedStart = Persistent.states.activeTime.activeSince;
        const validStoredSession = !Persistent.isNewHyprlandInstance
            && storedStart > 0
            && storedStart <= nowMs;

        if (validStoredSession) {
            activeSince = storedStart;
            reminderSent = Persistent.states.activeTime.reminderSent;
            checkReminder();
        } else {
            endSession();
        }
    }

    function checkReminder(): void {
        if (!initialized || reminderSent || !needsBreak)
            return;

        reminderSent = true;
        persist();
        Quickshell.execDetached([
            "notify-send",
            Translation.tr("Time for a break"),
            Translation.tr("You have been active for over an hour. Rest for at least 5 minutes to reset the timer."),
            "-a", "Shell"
        ]);
    }

    IdleMonitor {
        id: idleMonitor
        enabled: true
        timeout: root.idleTimeoutSeconds
        respectInhibitors: false

        onIsIdleChanged: {
            if (!root.initialized)
                return;
            if (isIdle)
                root.endSession();
            else
                root.startSession();
        }
    }

    IdleMonitor {
        id: inputMonitor
        enabled: true
        timeout: 0.25
        respectInhibitors: false

        onIsIdleChanged: {
            if (!isIdle && root.initialized && !root.suspended && root.activeSince <= 0)
                root.startSession();
        }
    }

    Timer {
        interval: 500
        repeat: false
        running: root.initialized && !root.suspended && root.activeSince <= 0
        onTriggered: {
            // A non-idle monitor after its timeout has elapsed proves that input
            // occurred after the monitor was registered.
            if (!inputMonitor.isIdle)
                root.startSession();
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.active
        onTriggered: {
            const currentTime = Date.now();
            if (currentTime < root.activeSince) {
                root.startSession();
                return;
            }
            root.nowMs = currentTime;
            root.checkReminder();
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged(): void {
            if (Persistent.ready)
                Qt.callLater(root.initialize);
        }
    }

    IpcHandler {
        target: "activeTime"

        function prepareForSleep(): void {
            root.suspended = true;
            root.endSession();
        }

        function resumeFromSleep(): void {
            root.suspended = false;
        }
    }

    Component.onCompleted: Qt.callLater(initialize)
}
