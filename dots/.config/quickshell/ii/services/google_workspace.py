#!/usr/bin/env python3
"""OAuth and REST bridge for the Quickshell Google Workspace service."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any


SCOPES = (
    "https://www.googleapis.com/auth/tasks",
    "https://www.googleapis.com/auth/calendar.readonly",
)
TASKS_BASE = "https://tasks.googleapis.com/tasks/v1"
CALENDAR_BASE = "https://www.googleapis.com/calendar/v3"


class WorkspaceError(RuntimeError):
    pass


def emit(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, ensure_ascii=True), flush=True)


def load_credentials(path: str) -> dict[str, str]:
    try:
        document = json.loads(Path(path).expanduser().read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise WorkspaceError(f"Could not read OAuth credentials: {error}") from error

    credentials = document.get("installed") or document.get("web") or document
    client_id = credentials.get("client_id")
    client_secret = credentials.get("client_secret")
    if not client_id or not client_secret:
        raise WorkspaceError("OAuth credentials must contain client_id and client_secret")
    return {
        "client_id": client_id,
        "client_secret": client_secret,
        "auth_uri": credentials.get("auth_uri", "https://accounts.google.com/o/oauth2/v2/auth"),
        "token_uri": credentials.get("token_uri", "https://oauth2.googleapis.com/token"),
    }


def request_json(
    url: str,
    *,
    method: str = "GET",
    token: str | None = None,
    body: dict[str, Any] | None = None,
    form: dict[str, str] | None = None,
) -> dict[str, Any]:
    headers = {"Accept": "application/json"}
    data = None
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode("utf-8")
    elif form is not None:
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        data = urllib.parse.urlencode(form).encode("utf-8")

    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read()
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            detail = json.loads(raw).get("error", {})
            message = detail.get("message") if isinstance(detail, dict) else str(detail)
        except json.JSONDecodeError:
            message = raw.decode("utf-8", errors="replace")
        raise WorkspaceError(f"Google API returned HTTP {error.code}: {message}") from error
    except urllib.error.URLError as error:
        raise WorkspaceError(f"Could not reach Google: {error.reason}") from error

    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError as error:
        raise WorkspaceError("Google returned an invalid JSON response") from error


def read_payload() -> dict[str, Any]:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError as error:
        raise WorkspaceError("The service sent an invalid request") from error
    if not isinstance(payload, dict):
        raise WorkspaceError("The service request must be a JSON object")
    return payload


def access_token(credentials: dict[str, str], refresh_token: str) -> str:
    if not refresh_token:
        raise WorkspaceError("Google Workspace is not connected")
    response = request_json(
        credentials["token_uri"],
        method="POST",
        form={
            "client_id": credentials["client_id"],
            "client_secret": credentials["client_secret"],
            "refresh_token": refresh_token,
            "grant_type": "refresh_token",
        },
    )
    token = response.get("access_token")
    if not token:
        raise WorkspaceError("Google did not return an access token")
    return token


def paginated(url: str, token: str) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    page_token = ""
    while True:
        separator = "&" if "?" in url else "?"
        page_url = url
        if page_token:
            page_url += separator + urllib.parse.urlencode({"pageToken": page_token})
        response = request_json(page_url, token=token)
        items.extend(response.get("items", []))
        page_token = response.get("nextPageToken", "")
        if not page_token:
            return items


def sync_workspace(credentials: dict[str, str], payload: dict[str, Any]) -> None:
    token = access_token(credentials, payload.get("refresh_token", ""))
    task_lists = paginated(f"{TASKS_BASE}/users/@me/lists?maxResults=100", token)
    tasks: list[dict[str, Any]] = []
    for task_list in task_lists:
        list_id = task_list.get("id", "")
        encoded_id = urllib.parse.quote(list_id, safe="")
        task_queries = (
            {
                "maxResults": 100,
                "showCompleted": "false",
                "showDeleted": "false",
                "showHidden": "false",
            },
            {
                "maxResults": 100,
                "showCompleted": "true",
                "showDeleted": "false",
                "showHidden": "true",
                "completedMin": (datetime.now(timezone.utc) - timedelta(days=90)).isoformat().replace("+00:00", "Z"),
            },
        )
        seen_task_ids: set[str] = set()
        list_tasks: list[dict[str, Any]] = []
        for query_params in task_queries:
            query = urllib.parse.urlencode(query_params)
            list_tasks.extend(paginated(f"{TASKS_BASE}/lists/{encoded_id}/tasks?{query}", token))
        for task in list_tasks:
            task_id = task.get("id", "")
            if task_id in seen_task_ids:
                continue
            seen_task_ids.add(task_id)
            tasks.append({
                "id": task_id,
                "taskListId": list_id,
                "taskListTitle": task_list.get("title", ""),
                "title": task.get("title", ""),
                "notes": task.get("notes", ""),
                "due": task.get("due", ""),
                "status": task.get("status", "needsAction"),
            })

    calendars = paginated(f"{CALENDAR_BASE}/users/me/calendarList?maxResults=250", token)
    now = datetime.now(timezone.utc)
    time_min = (now - timedelta(days=31)).isoformat().replace("+00:00", "Z")
    time_max = (now + timedelta(days=120)).isoformat().replace("+00:00", "Z")
    events: list[dict[str, Any]] = []
    normalized_calendars: list[dict[str, Any]] = []
    for calendar in calendars:
        if calendar.get("selected") is False:
            continue
        calendar_id = calendar.get("id", "")
        normalized_calendars.append({
            "id": calendar_id,
            "title": calendar.get("summaryOverride") or calendar.get("summary", ""),
            "color": calendar.get("backgroundColor", ""),
            "primary": calendar.get("primary", False),
        })
        query = urllib.parse.urlencode({
            "singleEvents": "true",
            "orderBy": "startTime",
            "showDeleted": "false",
            "maxResults": 250,
            "timeMin": time_min,
            "timeMax": time_max,
        })
        encoded_id = urllib.parse.quote(calendar_id, safe="")
        for event in paginated(f"{CALENDAR_BASE}/calendars/{encoded_id}/events?{query}", token):
            start = event.get("start", {})
            end = event.get("end", {})
            start_value = start.get("dateTime") or start.get("date", "")
            end_value = end.get("dateTime") or end.get("date", "")
            events.append({
                "id": event.get("id", ""),
                "calendarId": calendar_id,
                "calendarTitle": calendar.get("summaryOverride") or calendar.get("summary", ""),
                "color": calendar.get("backgroundColor", ""),
                "title": event.get("summary", "(Untitled event)"),
                "start": start_value,
                "end": end_value,
                "startDate": start_value[:10],
                "allDay": "date" in start,
                "htmlLink": event.get("htmlLink", ""),
            })

    emit({
        "type": "sync",
        "tasks": tasks,
        "taskLists": [{"id": item.get("id", ""), "title": item.get("title", "")} for item in task_lists],
        "events": events,
        "calendars": normalized_calendars,
        "syncedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    })


def mutate_task(credentials: dict[str, str], operation: str, payload: dict[str, Any]) -> None:
    token = access_token(credentials, payload.get("refresh_token", ""))
    list_id = urllib.parse.quote(payload.get("task_list_id") or "@default", safe="@")
    if operation == "add-task":
        title = str(payload.get("title", "")).strip()
        if not title:
            raise WorkspaceError("Task title cannot be empty")
        task = request_json(
            f"{TASKS_BASE}/lists/{list_id}/tasks",
            method="POST",
            token=token,
            body={"title": title},
        )
        emit({"type": "mutation", "task": task})
        return

    task_id = urllib.parse.quote(payload.get("task_id", ""), safe="")
    if not task_id:
        raise WorkspaceError("Task ID is required")
    url = f"{TASKS_BASE}/lists/{list_id}/tasks/{task_id}"
    if operation == "complete-task":
        request_json(url, method="PATCH", token=token, body={"status": "completed"})
    elif operation == "reopen-task":
        request_json(url, method="PATCH", token=token, body={"status": "needsAction", "completed": None})
    elif operation == "delete-task":
        request_json(url, method="DELETE", token=token)
    else:
        raise WorkspaceError(f"Unsupported operation: {operation}")
    emit({"type": "mutation"})


def authorize(credentials: dict[str, str]) -> None:
    state = secrets.token_urlsafe(32)
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    result: dict[str, str] = {}

    class CallbackHandler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802
            query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            result["state"] = query.get("state", [""])[0]
            result["code"] = query.get("code", [""])[0]
            result["error"] = query.get("error", [""])[0]
            success = bool(result["code"]) and result["state"] == state
            self.send_response(200 if success else 400)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            message = "Connected. You can close this tab." if success else "Authorization failed. Return to settings for details."
            self.wfile.write(f"<!doctype html><title>Google Workspace</title><p>{message}</p>".encode())

        def log_message(self, _format: str, *_args: Any) -> None:
            return

    server = HTTPServer(("127.0.0.1", 0), CallbackHandler)
    server.timeout = 180
    redirect_uri = f"http://127.0.0.1:{server.server_port}"
    auth_url = credentials["auth_uri"] + "?" + urllib.parse.urlencode({
        "client_id": credentials["client_id"],
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": " ".join(SCOPES),
        "access_type": "offline",
        "prompt": "consent",
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    })
    emit({"type": "authorization_url", "url": auth_url})
    server.handle_request()
    server.server_close()

    if result.get("error"):
        raise WorkspaceError(f"Google authorization failed: {result['error']}")
    if result.get("state") != state or not result.get("code"):
        raise WorkspaceError("Google authorization timed out or returned an invalid state")

    response = request_json(
        credentials["token_uri"],
        method="POST",
        form={
            "client_id": credentials["client_id"],
            "client_secret": credentials["client_secret"],
            "code": result["code"],
            "code_verifier": verifier,
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code",
        },
    )
    refresh_token = response.get("refresh_token")
    if not refresh_token:
        raise WorkspaceError("Google did not return a refresh token; revoke access and connect again")
    emit({"type": "authorized", "refreshToken": refresh_token})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("auth", "sync", "add-task", "complete-task", "reopen-task", "delete-task"))
    parser.add_argument("--credentials", required=True, help="Path to a Google Desktop OAuth client JSON file")
    args = parser.parse_args()

    try:
        credentials = load_credentials(args.credentials)
        if args.operation == "auth":
            authorize(credentials)
        else:
            payload = read_payload()
            if args.operation == "sync":
                sync_workspace(credentials, payload)
            else:
                mutate_task(credentials, args.operation, payload)
        return 0
    except WorkspaceError as error:
        emit({"type": "error", "message": str(error)})
        return 1
    except Exception as error:  # Keep QML errors structured without exposing secrets.
        emit({"type": "error", "message": f"Unexpected integration error: {error}"})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
