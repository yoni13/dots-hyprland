#!/usr/bin/env python3
"""ACP (Agent Client Protocol) chat client for dots-hyprland.

Connects to an ACP-compatible CLI agent (e.g. `opencode acp`,
`claude-agent-acp`), sends a conversation, and streams the agent's
response back as NDJSON to stdout.

Output format (one JSON object per line to stdout):
  {"type": "text",      "text": "..."}          – text chunk
  {"type": "thinking",  "text": "..."}          – reasoning/thinking chunk
  {"type": "tool_call", "name": "...", "status": "..."} – tool-use event
  {"type": "done",      "stopReason": "..."}    – response complete
  {"type": "error",     "message": "..."}       – fatal error

Usage:
  acp-chat.py --cmd '["opencode","acp"]' \
              --messages '[{"role":"user","rawContent":"Hello"}]' \
              [--system "You are helpful."] \
              [--model "opencode/mimo-v2.5-free"] \
              [--cwd "/tmp/acp-XXXXXX"]
"""

from __future__ import annotations
import argparse
import json
import os
import signal
import subprocess
import sys


def main() -> None:
    parser = argparse.ArgumentParser(description="ACP chat client")
    parser.add_argument("--cmd", required=True,
                        help="Agent command as JSON array, e.g. '[\"gemini\",\"--acp\"]'")
    parser.add_argument("--messages", required=True,
                        help="Conversation as JSON array of {role, rawContent} objects")
    parser.add_argument("--system", default="",
                        help="System prompt text")
    parser.add_argument("--model", default="",
                        help="Model ID to request via session/set_model after session creation "
                             "(empty = use the agent's default)")
    parser.add_argument("--cwd", default=os.getcwd(),
                        help="Working directory passed to the agent")
    args = parser.parse_args()

    try:
        agent_cmd: list[str] = json.loads(args.cmd)
        messages: list[dict] = json.loads(args.messages)
    except json.JSONDecodeError as exc:
        emit({"type": "error", "message": f"JSON parse error: {exc}"})
        sys.exit(1)

    if not isinstance(agent_cmd, list) or not agent_cmd:
        emit({"type": "error", "message": "Invalid agent command (must be a non-empty JSON array)"})
        sys.exit(1)

    if not messages:
        emit({"type": "error", "message": "No messages provided"})
        sys.exit(1)

    prompt_parts = build_prompt(messages, args.system)

    try:
        proc = subprocess.Popen(
            agent_cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            bufsize=0,
        )
    except FileNotFoundError:
        emit({"type": "error",
              "message": f"ACP agent not found: '{agent_cmd[0]}'. "
                         "Install it and ensure it is on your PATH."})
        sys.exit(1)
    except Exception as exc:
        emit({"type": "error", "message": f"Failed to start agent: {exc}"})
        sys.exit(1)

    def _cleanup(signum=None, frame=None) -> None:
        try:
            proc.terminate()
        except Exception:
            pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, _cleanup)
    signal.signal(signal.SIGINT, _cleanup)

    state: dict = {
        "req_id": 0,
        "init_id": None,
        "new_session_id": None,
        "set_model_id": None,   # optional; only set when --model is given
        "session_id": None,
        "prompt_id": None,
        "done": False,
    }

    def next_id() -> str:
        state["req_id"] += 1
        return str(state["req_id"])

    def write_json(obj: dict) -> None:
        assert proc.stdin is not None
        proc.stdin.write((json.dumps(obj) + "\n").encode())
        proc.stdin.flush()

    def send_request(method: str, params: dict | None = None) -> str:
        rid = next_id()
        msg: dict = {"jsonrpc": "2.0", "id": rid, "method": method}
        if params is not None:
            msg["params"] = params
        write_json(msg)
        return rid

    def send_response(rid: str, result: dict) -> None:
        write_json({"jsonrpc": "2.0", "id": rid, "result": result})

    def send_error_response(rid: str, code: int, message: str) -> None:
        write_json({"jsonrpc": "2.0", "id": rid,
                    "error": {"code": code, "message": message}})

    state["init_id"] = send_request("initialize", {
        "protocolVersion": 1,
        "clientCapabilities": {
            "fs": {"readTextFile": True, "writeTextFile": True},
        },
    })

    try:
        assert proc.stdout is not None
        for raw in proc.stdout:
            line = raw.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue

            msg_id     = msg.get("id")
            msg_method = msg.get("method")
            msg_result = msg.get("result")
            msg_error  = msg.get("error")
            msg_params = msg.get("params") or {}

            if msg_id is not None and msg_result is not None:
                # Response to one of our outgoing requests
                if msg_id == state["init_id"]:
                    state["new_session_id"] = send_request("session/new", {
                        "cwd": args.cwd,
                        "mcpServers": [],
                    })
                elif msg_id == state["new_session_id"]:
                    state["session_id"] = msg_result.get("sessionId")
                    if args.model:
                        # Ask the agent to switch to the requested model.
                        # Not all agents implement this; errors are handled below.
                        state["set_model_id"] = send_request("session/set_model", {
                            "sessionId": state["session_id"],
                            "modelId": args.model,
                        })
                    else:
                        state["prompt_id"] = send_request("session/prompt", {
                            "sessionId": state["session_id"],
                            "prompt": prompt_parts,
                        })
                elif msg_id == state["set_model_id"]:
                    # Model set (or agent silently accepted); proceed with the prompt.
                    state["prompt_id"] = send_request("session/prompt", {
                        "sessionId": state["session_id"],
                        "prompt": prompt_parts,
                    })
                elif msg_id == state["prompt_id"]:
                    emit({"type": "done",
                          "stopReason": msg_result.get("stopReason", "end_turn")})
                    state["done"] = True
                    break

            elif msg_id is not None and msg_error is not None:
                if msg_id == state["set_model_id"]:
                    # Agent doesn't support session/set_model — carry on anyway.
                    state["set_model_id"] = None
                    state["prompt_id"] = send_request("session/prompt", {
                        "sessionId": state["session_id"],
                        "prompt": prompt_parts,
                    })
                else:
                    emit({"type": "error",
                          "message": msg_error.get("message", "Unknown agent error")})
                    state["done"] = True
                    break

            elif msg_id is not None and msg_method is not None:
                # Agent is making a request to us (client-side method)
                _handle_client_request(msg_id, msg_method, msg_params,
                                       args.cwd, send_response, send_error_response)

            elif msg_id is None and msg_method is not None:
                # Notification from agent (no id)
                _handle_notification(msg_method, msg_params)

    except BrokenPipeError:
        pass
    except Exception as exc:
        if not state["done"]:
            emit({"type": "error", "message": str(exc)})
    finally:
        try:
            assert proc.stdin is not None
            proc.stdin.close()
        except Exception:
            pass
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()


def build_prompt(messages: list[dict], system_prompt: str) -> list[dict]:
    """Convert conversation history + system prompt into ACP prompt parts."""
    parts: list[dict] = []

    if len(messages) > 1:
        lines: list[str] = []
        if system_prompt:
            lines.append(f"[System instructions: {system_prompt}]\n")
        for msg in messages[:-1]:
            role    = msg.get("role", "user")
            content = msg.get("rawContent") or msg.get("content", "")
            if role == "user":
                lines.append(f"**User**: {content}")
            elif role == "assistant":
                lines.append(f"**Assistant**: {content}")
        lines.append("---")
        parts.append({"type": "text", "text": "\n\n".join(lines) + "\n\n"})
    elif system_prompt:
        parts.append({"type": "text",
                      "text": f"[System instructions: {system_prompt}]\n\n"})

    last    = messages[-1]
    content = last.get("rawContent") or last.get("content", "")
    parts.append({"type": "text", "text": content})
    return parts


def _handle_client_request(rid: str, method: str, params: dict, cwd: str,
                            respond, respond_error) -> None:
    """Handle a JSON-RPC request sent from the agent to the client."""
    if method == "session/request_permission":
        options   = params.get("options") or []
        option_id = options[0].get("optionId", "allow_once") if options else "allow_once"
        respond(rid, {"outcome": {"outcome": "selected", "optionId": option_id}})

    elif method == "fs/read_text_file":
        path = params.get("path", "")
        if not os.path.isabs(path):
            path = os.path.join(cwd, path)
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                respond(rid, {"content": fh.read()})
        except Exception as exc:
            respond_error(rid, -32000, str(exc))

    elif method == "fs/write_text_file":
        path    = params.get("path", "")
        content = params.get("content", "")
        if not os.path.isabs(path):
            path = os.path.join(cwd, path)
        try:
            os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(content)
            respond(rid, {})
        except Exception as exc:
            respond_error(rid, -32000, str(exc))

    elif method == "elicitation/create":
        # Cancel any interactive elicitation requests
        respond(rid, {"action": "cancel"})

    else:
        # Unknown client method — return empty success so the agent can continue
        respond(rid, {})


def _handle_notification(method: str, params: dict) -> None:
    """Handle a JSON-RPC notification from the agent."""
    if method != "session/update":
        return

    update      = params.get("update") or {}
    update_type = update.get("sessionUpdate", "")

    if update_type == "agent_message_chunk":
        content = update.get("content") or {}
        ctype   = content.get("type", "")
        text    = content.get("text", "")
        if ctype == "text" and text:
            emit({"type": "text", "text": text})
        elif ctype == "thinking" and text:
            emit({"type": "thinking", "text": text})

    elif update_type == "agent_thought_chunk":
        content = update.get("content") or {}
        text    = content.get("text", "")
        if text:
            emit({"type": "thinking", "text": text})

    elif update_type == "tool_call":
        title  = update.get("title", "")
        status = update.get("status", "")
        if title:
            emit({"type": "tool_call", "name": title, "status": status})


def emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


if __name__ == "__main__":
    main()
