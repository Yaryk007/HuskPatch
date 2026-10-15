package husk;

import android.content.pm.PackageManager;
import java.util.HashMap;

/**
 * HuskPatch: Android's runtime permissions, answered by the host. A request shows Android's permission dialog (and the
 * iPhone's own, for what iOS also guards, such as the camera); special app access (display over other apps and the like)
 * shows its Settings page. The answer comes back through the input queue (phase 11) to deliver(), on the main thread.
 */
public final class Permissions {
    private Permissions() {}

    /** What the host says of a permission: husk-tl-unity-app.h's HUSK_PERM_*. */
    public static final int GRANTED = 0, DENIED = 1, DENIED_FOREVER = 2, UNSET = 3;

    public interface Callback { void done(String[] perms, int[] results); }

    private static final HashMap<Integer, Object[]> sPending = new HashMap<>();
    private static int sNext = 1;

    public static int state(String perm) {
        if (perm == null) return DENIED;
        try { return Native.permissionState(perm); } catch (Throwable t) { return GRANTED; }
    }

    /** Context.checkPermission. */
    public static int check(String perm) {
        return state(perm) == GRANTED ? PackageManager.PERMISSION_GRANTED : PackageManager.PERMISSION_DENIED;
    }

    /** Activity.shouldShowRequestPermissionRationale: turned down once, and not for good. */
    public static boolean rationale(String perm) { return state(perm) == DENIED; }

    /** A special permission (Settings' special app access): its own default until the user has chosen, as on a new phone. */
    public static boolean special(String perm, boolean byDefault) {
        int s = state(perm);
        return s == UNSET ? byDefault : s == GRANTED;
    }

    public static void request(String[] perms, Callback cb) {
        if (perms == null) perms = new String[0];
        final String[] asked = perms.clone();
        if (asked.length == 0) { cb.done(asked, new int[0]); return; }
        int id;
        synchronized (sPending) { id = sNext++; sPending.put(id, new Object[] { asked, cb }); }
        try {
            Native.requestPermissions(id, asked);
        } catch (Throwable t) {
            /* an older runtime without the call: everything was always granted there */
            synchronized (sPending) { sPending.remove(id); }
            int[] r = new int[asked.length];
            cb.done(asked, r);
        }
    }

    /** From the input queue: bit i of `granted` set when perms[i] was granted. */
    static void deliver(int id, int granted) {
        Object[] p;
        synchronized (sPending) { p = sPending.remove(id); }
        if (p == null) return;
        String[] perms = (String[]) p[0];
        int[] r = new int[perms.length];
        for (int i = 0; i < perms.length; i++)
            r[i] = i < 32 && (granted & (1 << i)) != 0 ? PackageManager.PERMISSION_GRANTED : PackageManager.PERMISSION_DENIED;
        try { ((Callback) p[1]).done(perms, r); }
        catch (Throwable t) { android.util.Log.e("Husk", "a permission result's receiver failed", t); }
    }

    /** The special app access a Settings action opens a page for, or null. */
    public static String specialFor(String action) {
        if (action == null) return null;
        switch (action) {
            case "android.settings.action.MANAGE_OVERLAY_PERMISSION": return "android.permission.SYSTEM_ALERT_WINDOW";
            case "android.settings.action.MANAGE_WRITE_SETTINGS": return "android.permission.WRITE_SETTINGS";
            case "android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION":
            case "android.settings.MANAGE_ALL_FILES_ACCESS_PERMISSION": return "android.permission.MANAGE_EXTERNAL_STORAGE";
            case "android.settings.MANAGE_UNKNOWN_APP_SOURCES": return "android.permission.REQUEST_INSTALL_PACKAGES";
            case "android.settings.REQUEST_SCHEDULE_EXACT_ALARM": return "android.permission.SCHEDULE_EXACT_ALARM";
            case "android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS":
            case "android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS": return "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS";
            case "android.settings.USAGE_ACCESS_SETTINGS": return "android.permission.PACKAGE_USAGE_STATS";
            case "android.settings.APP_NOTIFICATION_SETTINGS":
            case "android.settings.ALL_APPS_NOTIFICATION_SETTINGS": return "android.permission.POST_NOTIFICATIONS";
            case "android.settings.APPLICATION_DETAILS_SETTINGS":
            case "android.settings.MANAGE_APPLICATIONS_SETTINGS": return "husk.APP_INFO";
            default: return null;
        }
    }
}
