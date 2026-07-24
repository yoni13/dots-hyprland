import QtQuick

QtObject {
    function buildEndpoint(model: AiModel): string { throw new Error("Not implemented") }
    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string): var { throw new Error("Not implemented") }
    function buildAuthorizationHeader(apiKeyEnvVarName: string): string { throw new Error("Not implemented") }
    function parseResponseLine(line: string, message: AiMessageData): var { throw new Error("Not implemented") }
    function onRequestFinished(message: AiMessageData): var { return {} } // Default: no special handling
    function reset(): void { } // Reset any internal state if needed
    function buildScriptFileSetup(filePath: string): string { return "" } // Default: no setup
    function finalizeScriptContent(scriptContent: string): string { return scriptContent } // Optionally modify/finalize script
}
