pragma Singleton
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    function isRealScreen(screen) {
        const monitor = screen == null ? null : Hyprland.monitorFor(screen);
        return monitor != null && monitor.id >= 0 && monitor.name !== "FALLBACK";
    }

    function realScreens() {
        return Quickshell.screens.filter(screen => root.isRealScreen(screen));
    }
}
