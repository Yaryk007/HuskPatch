// SPDX-License-Identifier: GPL-2.0-or-later
package husk;

import android.util.TypedValue;

/**
 * HuskPatch: Material You's dynamic colours, from Husk's Android 16 style.
 *
 * Android 12 and later give apps a palette made from the wallpaper as 65 framework colours: system_neutral1,
 * system_neutral2, system_accent1, system_accent2 and system_accent3, each in 13 shades (0, 10, 50, 100 ... 900, 1000).
 * Material 3 apps (DynamicColors, ThemeOverlay.Material3.DynamicColors) and the platform's DeviceDefault themes are
 * drawn from them. Husk sets HUSK_DYNAMIC_COLORS to its own palette, in that id order, when "Material You in Apps" is
 * on; every resource lookup (Resources.huskValue) answers those ids from it instead of framework-res's defaults.
 */
public final class DynamicColors {
    private static final int FIRST = 0x0106001d; /* android.R.color.system_neutral1_0 */
    private static final int LAST = 0x0106005d;  /* android.R.color.system_accent3_1000 */
    private static int[] sColors;
    private static boolean sLoaded;

    private DynamicColors() {}

    /** Fill `out` with the palette's colour when `id` is one of the 65 and a palette was given. */
    public static boolean apply(int id, TypedValue out) {
        if (id < FIRST || id > LAST) return false;
        int[] c = colors();
        if (c == null) return false;
        out.type = TypedValue.TYPE_INT_COLOR_ARGB8;
        out.data = c[id - FIRST];
        out.string = null;
        out.resourceId = id;
        out.sourceResourceId = id;
        out.assetCookie = 1;
        out.changingConfigurations = 0;
        out.density = 0;
        return true;
    }

    private static synchronized int[] colors() {
        if (!sLoaded) {
            sLoaded = true;
            String s = System.getenv("HUSK_DYNAMIC_COLORS");
            if (s != null) {
                String[] p = s.split(",");
                if (p.length == LAST - FIRST + 1) {
                    int[] c = new int[p.length];
                    try {
                        for (int i = 0; i < p.length; i++) c[i] = (int) Long.parseLong(p[i].trim(), 16);
                        sColors = c;
                    } catch (NumberFormatException e) {
                        sColors = null;
                    }
                }
            }
        }
        return sColors;
    }
}
