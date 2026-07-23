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
    readonly property bool credentialsReady: Object.keys(clientCredentials).length > 0
    readonly property bool connected: refreshToken.length > 0
    readonly property bool busy: importingCredentials || awaitingCredentialSave || authorizing || syncing || apiProcess.running || deleteCredentialsFileProcess.running

    property string refreshToken: ""
    property var clientCredentials: ({})
    property bool importingCredentials: false
    property bool awaitingCredentialSave: false
    property bool authorizing: false
    property bool syncing: false
    property string errorMessage: ""
    property string credentialNotice: ""
    property string pendingCredentialDeletionPath: Config.options?.googleWorkspace.pendingCredentialDeletionPath ?? ""
    property string credentialImportPath: ""
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
        if (importingCredentials)
            return Translation.tr("Importing OAuth credentials");
        if (!credentialsReady)
            return Translation.tr("Import a Desktop OAuth client JSON file");
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
        const storedCredentials = KeyringStorage.keyringData?.googleWorkspace?.clientCredentials ?? {};
        const tokenChanged = storedToken !== root.refreshToken;
        const credentialsChanged = JSON.stringify(storedCredentials) !== JSON.stringify(root.clientCredentials);
        root.refreshToken = storedToken;
        root.clientCredentials = storedCredentials;
        if (!root.connected) {
            root.tasks = [];
            root.taskLists = [];
            root.events = [];
            root.calendars = [];
            root.lastSync = "";
        } else if (root.enabled && root.credentialsReady && (tokenChanged || credentialsChanged || !root.lastSync)) {
            root.refresh();
        }
    }

    function importCredentials(path) {
        const trimmedPath = path.trim();
        if (!trimmedPath) {
            root.errorMessage = Translation.tr("Choose a Desktop OAuth client JSON file first");
            return;
        }
        root.errorMessage = "";
        root.credentialNotice = "";
        root.credentialImportPath = trimmedPath;
        root.importingCredentials = true;
        importCredentialsProcess.command = ["python3", root.helperPath, "import-credentials", "--credentials", trimmedPath];
        importCredentialsProcess.running = true;
    }

    function deleteImportedCredentialsFile() {
        if (!root.pendingCredentialDeletionPath || deleteCredentialsFileProcess.running)
            return;
        deleteCredentialsFileProcess.command = ["rm", "--", root.pendingCredentialDeletionPath];
        deleteCredentialsFileProcess.running = true;
    }

    function keepImportedCredentialsFile() {
        root.pendingCredentialDeletionPath = "";
        Config.options.googleWorkspace.pendingCredentialDeletionPath = "";
        root.credentialNotice = Translation.tr("OAuth credentials remain securely stored in the OS keyring");
    }

    function connectAccount() {
        if (!root.credentialsReady) {
            root.errorMessage = Translation.tr("Import OAuth credentials first");
            return;
        }
        root.errorMessage = "";
        root.authorizing = true;
        authProcess.command = ["python3", root.helperPath, "auth"];
        authProcess.stdinEnabled = true;
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
        if (apiProcess.running || !root.connected || !root.credentialsReady)
            return;
        root.errorMessage = "";
        root.pendingOperation = operation;
        root.pendingPayload = Object.assign({
            "refresh_token": root.refreshToken,
            "credentials": root.clientCredentials
        }, payload || {});
        root.syncing = operation === "sync";
        apiProcess.command = ["python3", root.helperPath, operation];
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
        if (message.type === "credentials_imported") {
            root.clientCredentials = message.credentials || {};
            root.awaitingCredentialSave = true;
            KeyringStorage.setNestedField(["googleWorkspace", "clientCredentials"], root.clientCredentials);
            root.credentialImportPath = message.sourcePath || root.credentialImportPath;
            root.errorMessage = "";
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

        function onDataSaved() {
            if (!root.awaitingCredentialSave)
                return;
            root.awaitingCredentialSave = false;
            root.pendingCredentialDeletionPath = root.credentialImportPath;
            Config.options.googleWorkspace.pendingCredentialDeletionPath = root.pendingCredentialDeletionPath;
            root.credentialNotice = Translation.tr("Credentials imported securely. Delete the original JSON file?");
            Config.options.googleWorkspace.credentialsPath = "";
        }

        function onDataSaveFailed() {
            if (!root.awaitingCredentialSave)
                return;
            root.awaitingCredentialSave = false;
            root.errorMessage = Translation.tr("Could not save OAuth credentials to the OS keyring");
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
        id: importCredentialsProcess

        stdout: SplitParser {
            onRead: data => root.handleMessage(data)
        }
        onExited: (exitCode, _exitStatus) => {
            root.importingCredentials = false;
            if (exitCode !== 0 && !root.errorMessage)
                root.errorMessage = Translation.tr("Could not import OAuth credentials");
        }
    }

    Process {
        id: deleteCredentialsFileProcess

        onExited: (exitCode, _exitStatus) => {
            if (exitCode === 0) {
                root.pendingCredentialDeletionPath = "";
                Config.options.googleWorkspace.pendingCredentialDeletionPath = "";
                root.credentialNotice = Translation.tr("Original OAuth credential file deleted");
            } else {
                root.errorMessage = Translation.tr("Could not delete the original OAuth credential file");
            }
        }
    }

    Process {
        id: authProcess

        stdout: SplitParser {
            onRead: data => root.handleMessage(data)
        }
        onRunningChanged: {
            if (!authProcess.running)
                return;
            authProcess.write(JSON.stringify({"credentials": root.clientCredentials}));
            authProcess.stdinEnabled = false;
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
