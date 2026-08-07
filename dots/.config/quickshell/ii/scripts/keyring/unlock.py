#!/usr/bin/env python3

import os
import sys

from gi.repository import Gio, GLib


password = os.environ.pop("UNLOCK_PASSWORD", "")
if not password:
    print("Keyring unlock password is missing", file=sys.stderr)
    raise SystemExit(1)

try:
    connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    session_reply = connection.call_sync(
        "org.freedesktop.secrets",
        "/org/freedesktop/secrets",
        "org.freedesktop.Secret.Service",
        "OpenSession",
        GLib.Variant("(sv)", ("plain", GLib.Variant("s", ""))),
        GLib.VariantType("(vo)"),
        Gio.DBusCallFlags.NONE,
        5000,
        None,
    )
    _, session_path = session_reply.unpack()

    connection.call_sync(
        "org.freedesktop.secrets",
        "/org/freedesktop/secrets",
        "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface",
        "UnlockWithMasterPassword",
        GLib.Variant(
            "(o(oayays))",
            (
                "/org/freedesktop/secrets/collection/login",
                (session_path, b"", password.encode(), "text/plain"),
            ),
        ),
        None,
        Gio.DBusCallFlags.NONE,
        5000,
        None,
    )
except GLib.Error as error:
    print(f"Keyring unlock failed: {error.message}", file=sys.stderr)
    raise SystemExit(1)
