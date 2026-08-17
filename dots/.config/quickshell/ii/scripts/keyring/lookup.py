#!/usr/bin/env python3

import sys

from gi.repository import Gio, GLib


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

    search_reply = connection.call_sync(
        "org.freedesktop.secrets",
        "/org/freedesktop/secrets",
        "org.freedesktop.Secret.Service",
        "SearchItems",
        GLib.Variant("(a{ss})", ({"application": "illogical-impulse"},)),
        GLib.VariantType("(aoao)"),
        Gio.DBusCallFlags.NONE,
        5000,
        None,
    )
    unlocked_items, locked_items = search_reply.unpack()

    if not unlocked_items:
        print("locked" if locked_items else "not found")
        raise SystemExit(2 if locked_items else 1)

    secret_reply = connection.call_sync(
        "org.freedesktop.secrets",
        unlocked_items[0],
        "org.freedesktop.Secret.Item",
        "GetSecret",
        GLib.Variant("(o)", (session_path,)),
        GLib.VariantType("((oayays))"),
        Gio.DBusCallFlags.NONE,
        5000,
        None,
    )
    _, _, secret, _ = secret_reply.unpack()[0]
    sys.stdout.buffer.write(bytes(secret))
except GLib.Error as error:
    print(f"Keyring lookup failed: {error.message}", file=sys.stderr)
    raise SystemExit(2)
