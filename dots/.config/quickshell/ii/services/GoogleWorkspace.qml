pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string helperPath: Quickshell.shellPath("services/google_workspace.py")
    readonly property bool enabled: Config.options?.googleWorkspace.enable ?? false
    readonly property string credentialsPath: Config.options?.googleWorkspace.credentialsPath ?? ""
    readonly property bool connected: refreshToken.length > 0
    readonly property bool busy: authorizing || syncing || apiProcess.running

    property string refreshToken: ""
    property bool authorizing: false
    property bool syncing: false
    property string errorMessage: ""
    property string lastSync: ""
    property var tasks: []
    property var taskLists: []
    property var events: []
    property var calendars: []
    property var pendingPayload: ({})
    property string pendingOperation: ""

    readonly property string statusText: {
        if (errorMessage)
            return errorMessage;
        if (authorizing)
            return Translation.tr("Waiting for Google authorization");
        if (syncing)
            return Translation.tr("Syncing Google Tasks and Calendar");
        if (!connected)
            return Translation.tr("Not connected");
        if (lastSync)
            return Translation.tr("Connected - %1 tasks, %2 events - last synced %3")
                .arg(tasks.length)
                .arg(events.length)
                .arg(new Date(lastSync).toLocaleTimeString(Qt.locale(), "HH:mm"));
        return Translation.tr("Connected");
    }

    function loadKeyring() {
        if (!KeyringStorage.loaded) {
            KeyringStorage.fetchKeyringData();
            return;
        }
        const storedToken = KeyringStorage.keyringData?.googleWorkspace?.refreshToken ?? "";
        const tokenChanged = storedToken !== root.refreshToken;
        root.refreshToken = storedToken;
        if (!root.connected) {
            root.tasks = [];
            root.taskLists = [];
            root.events = [];
            root.calendars = [];
            root.lastSync = "";
        } else if (root.enabled && root.credentialsPath && (tokenChanged || !root.lastSync)) {
            root.refresh();
        }
    }

    function connectAccount() {
        if (!root.credentialsPath) {
            root.errorMessage = Translation.tr("Choose a Desktop OAuth client JSON file first");
            return;
        }
        root.errorMessage = "";
        root.authorizing = true;
        authProcess.command = ["python3", root.helperPath, "auth", "--credentials", root.credentialsPath];
        authProcess.running = true;
    }

    function disconnectAccount() {
        KeyringStorage.setNestedField(["googleWorkspace", "refreshToken"], "");
        root.refreshToken = "";
        root.tasks = [];
        root.taskLists = [];
        root.events = [];
        root.calendars = [];
        root.lastSync = "";
        root.errorMessage = "";
    }

    function runApi(operation, payload) {
        if (apiProcess.running || !root.connected || !root.credentialsPath)
            return;
        root.errorMessage = "";
        root.pendingOperation = operation;
        root.pendingPayload = Object.assign({"refresh_token": root.refreshToken}, payload || {});
        root.syncing = operation === "sync";
        apiProcess.command = ["python3", root.helperPath, operation, "--credentials", root.credentialsPath];
        apiProcess.stdinEnabled = true;
        apiProcess.running = true;
    }

    function refresh() {
        root.runApi("sync", {});
    }

    function addTask(title) {
        root.runApi("add-task", {"title": title});
    }

    function completeTask(task) {
        root.runApi("complete-task", {
            "task_id": task.id,
            "task_list_id": task.taskListId
        });
    }

    function reopenTask(task) {
        root.runApi("reopen-task", {
            "task_id": task.id,
            "task_list_id": task.taskListId
        });
    }

    function deleteTask(task) {
        root.runApi("delete-task", {
            "task_id": task.id,
            "task_list_id": task.taskListId
        });
    }

    function handleMessage(data) {
        let message;
        try {
            message = JSON.parse(data);
        } catch (error) {
            root.errorMessage = Translation.tr("Google integration returned invalid data");
            return;
        }
        if (message.type === "error") {
            root.errorMessage = message.message || Translation.tr("Google integration failed");
            return;
        }
        if (message.type === "authorization_url") {
            Qt.openUrlExternally(message.url);
            return;
        }
        if (message.type === "authorized") {
            root.refreshToken = message.refreshToken;
            KeyringStorage.setNestedField(["googleWorkspace", "refreshToken"], message.refreshToken);
            root.errorMessage = "";
            return;
        }
        if (message.type === "sync") {
            root.tasks = message.tasks || [];
            root.taskLists = message.taskLists || [];
            root.events = message.events || [];
            root.calendars = message.calendars || [];
            root.lastSync = message.syncedAt || new Date().toISOString();
            root.errorMessage = "";
            console.log(`[GoogleWorkspace] Synced ${root.tasks.length} tasks and ${root.events.length} events from ${root.calendars.length} calendars`);
        }
    }

    Component.onCompleted: root.loadKeyring()

    Connections {
        target: KeyringStorage

        function onLoadedChanged() {
            root.loadKeyring();
        }

        function onDataChanged() {
            root.loadKeyring();
        }

        function onKeyringDataChanged() {
            root.loadKeyring();
        }
    }

    Connections {
        target: Config

        function onReadyChanged() {
            if (Config.ready && root.enabled && root.connected)
                root.refresh();
        }
    }

    Timer {
        interval: Math.max(5, Config.options?.googleWorkspace.refreshInterval ?? 15) * 60000
        repeat: true
        triggeredOnStart: true
        running: Config.ready && root.enabled && root.connected
        onTriggered: root.refresh()
    }

    Timer {
        interval: 10000
        repeat: true
        triggeredOnStart: true
        running: Config.ready && root.enabled
        onTriggered: KeyringStorage.fetchKeyringData()
    }

    Process {
        id: authProcess

        stdout: SplitParser {
            onRead: data => root.handleMessage(data)
        }
        onExited: (exitCode, _exitStatus) => {
            root.authorizing = false;
            if (exitCode === 0 && root.connected)
                root.refresh();
            else if (exitCode !== 0 && !root.errorMessage)
                root.errorMessage = Translation.tr("Google authorization failed");
        }
    }

    Process {
        id: apiProcess

        stdout: SplitParser {
            onRead: data => root.handleMessage(data)
        }
        onRunningChanged: {
            if (!apiProcess.running)
                return;
            apiProcess.write(JSON.stringify(root.pendingPayload));
            apiProcess.stdinEnabled = false;
        }
        onExited: (exitCode, _exitStatus) => {
            const completedOperation = root.pendingOperation;
            root.syncing = false;
            root.pendingOperation = "";
            root.pendingPayload = {};
            if (exitCode === 0 && completedOperation !== "sync")
                root.refresh();
            else if (exitCode !== 0 && !root.errorMessage)
                root.errorMessage = Translation.tr("Google request failed");
        }
    }
}
