import QtQuick
import qs.modules.common
import qs.modules.common.functions as CF

/**
 * API strategy for ACP (Agent Client Protocol) agents.
 *
 * Instead of issuing a curl request, this strategy spawns an ACP-compatible
 * CLI tool (e.g. `opencode acp` or `claude-agent-acp`) via acp-chat.py and
 * streams text back through the existing Process/SplitParser pipeline.
 *
 * The model's `endpoint` field must be the shell command for the agent,
 * e.g. "opencode acp" or "claude-agent-acp".
 *
 * Output from acp-chat.py is NDJSON; each line is one of:
 *   {"type":"text",     "text":"..."}
 *   {"type":"thinking", "text":"..."}
 *   {"type":"tool_call","name":"...","status":"..."}
 *   {"type":"done",     "stopReason":"..."}
 *   {"type":"error",    "message":"..."}
 */
ApiStrategy {
    // State stored per-request and consumed in finalizeScriptContent / parseResponseLine
    property var acpMessages: []
    property string acpSystemPrompt: ""
    property var acpModel: null
    property bool acpInThinking: false

    function buildEndpoint(model: AiModel): string {
        return model.endpoint || ""
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string,
                              temperature: real, tools: list<var>, filePath: string) {
        // Store what we need; the actual script is built in finalizeScriptContent.
        acpMessages = messages.map(function(m) {
            return {
                role: m.role,
                rawContent: m.rawContent || m.content || ""
            }
        });
        acpSystemPrompt = systemPrompt;
        acpModel = model;
        return {};
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return ""; // ACP agents handle their own auth
    }

    /**
     * Replace the entire curl script with a python3 invocation of acp-chat.py.
     * The `_ignored` parameter contains the curl command built by Ai.qml — we
     * discard it completely and build our own script.
     */
    function finalizeScriptContent(_ignored: string): string {
        const scriptPath = Directories.scriptPath.replace(/^file:\/\//, "");
        const acpScript  = scriptPath + "/ai/acp-chat.py";

        // Build the agent command array from the model's endpoint string
        const cmdWords = (acpModel?.endpoint || "").split(/\s+/).filter(function(s) { return s.length > 0; });
        const cmdJson  = JSON.stringify(cmdWords);

        const msgsJson  = CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(acpMessages));
        const sysText   = CF.StringUtils.shellSingleQuoteEscape(acpSystemPrompt);
        const modelFlag = acpModel?.model
            ? " --model '" + CF.StringUtils.shellSingleQuoteEscape(acpModel.model) + "'"
            : "";

        // Use mktemp so each session gets an isolated, random working directory.
        // The directory is removed once the agent exits.
        return "#!/usr/bin/env bash\n"
            + "ACP_CWD=$(mktemp -d /tmp/acp-XXXXXX)\n"
            + "trap 'rm -rf \"$ACP_CWD\"' EXIT\n"
            + "python3 '" + acpScript + "'"
            + " --cmd '" + cmdJson + "'"
            + " --messages '" + msgsJson + "'"
            + " --system '" + sysText + "'"
            + modelFlag
            + " --cwd \"$ACP_CWD\""
            + "\n";
    }

    function parseResponseLine(line: string, message: AiMessageData) {
        if (!line || !line.trim()) return {};

        try {
            const data = JSON.parse(line.trim());

            if (data.type === "text") {
                if (acpInThinking) {
                    acpInThinking = false;
                    message.content    += "\n\n</think>\n\n";
                    message.rawContent += "\n\n</think>\n\n";
                }
                message.content    += data.text || "";
                message.rawContent += data.text || "";

            } else if (data.type === "thinking") {
                if (!acpInThinking) {
                    acpInThinking = true;
                    message.content    += "\n\n<think>\n\n";
                    message.rawContent += "\n\n<think>\n\n";
                }
                message.content    += data.text || "";
                message.rawContent += data.text || "";

            } else if (data.type === "tool_call") {
                if (data.name) {
                    const info = "\n\n*" + data.name + " — " + (data.status || "running") + "*\n\n";
                    message.content    += info;
                    message.rawContent += info;
                }

            } else if (data.type === "done") {
                if (acpInThinking) {
                    acpInThinking = false;
                    message.content    += "\n\n</think>\n\n";
                    message.rawContent += "\n\n</think>\n\n";
                }
                return { finished: true };

            } else if (data.type === "error") {
                const errMsg = "\n\n**Error**: " + (data.message || "Unknown error") + "\n\n";
                message.content    += errMsg;
                message.rawContent += errMsg;
                return { finished: true };
            }

        } catch (_) {}

        return {};
    }

    function onRequestFinished(message: AiMessageData) {
        if (acpInThinking) {
            acpInThinking = false;
            message.content    += "\n\n</think>\n\n";
            message.rawContent += "\n\n</think>\n\n";
        }
        return { finished: true };
    }

    function reset() {
        acpInThinking  = false;
        acpMessages    = [];
        acpSystemPrompt = "";
        acpModel       = null;
    }
}
