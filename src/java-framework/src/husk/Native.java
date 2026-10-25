package husk;

/** What Husk's runtime does for the framework: logging, the app's files and assets, the screen, input, the host's keyboard and clipboard. */
public final class Native {
    private Native() {}
    public static native void log(int priority, String tag, String msg);
    public static native byte[] readAsset(String path);
    public static native String[] listAssets(String dir);
    public static native long assetFd(String path);          // fd << 40 | offset; -1 when compressed or missing
    public static native long assetLength(String path);
    /** A file in one of the APKs: 0 the app's, 1 the platform's resources (framework-res), 2.. the app's split APKs. */
    public static native byte[] readApkFile(int apk, String path);
    public static native long apkFileFd(int apk, String path);
    public static native long apkFileLength(int apk, String path);
    public static native String apkPath();
    /** The app's split APKs (a Google Play install: libraries, resources, asset packs), in the order they were given. */
    public static native String[] splitPaths();
    /** The NDK looper of this thread: made with the Java one, and its callbacks run between messages. */
    public static native void nativeLooperPrepare();
    public static native boolean nativeLooperPoll();
    /** Class.getClassLoader for the app's own classes. */
    public static native void setAppClassLoader(ClassLoader loader);
    public static native String dataDir();
    public static native String externalDir();
    public static native String packageName();
    public static native int screenWidth();
    public static native int screenHeight();
    public static native float density();
    public static native void startGL(Object view, Object renderer, int esVersion);
    public static native void requestRender();
    public static native void setContentView(Object view);
    public static native int[] pollInput();                  // packed touch events, or null
    public static native String[] pollText();                // typed text, deletes and actions from the keyboard
    public static native void showKeyboard(boolean show, int inputType, int imeOptions);
    public static native void setClipboard(String text);
    public static native String getClipboard();
    public static native void share(String text);
    public static native void setOrientation(int androidOrientation);
    public static native int[] insets();
    public static native boolean nightMode();                // the phone is in dark mode                     // left, top, right, bottom of the screen the app must keep clear
    public static native boolean is24Hour();                 // the phone's clock shows 24-hour time
    public static native void vibrate(long ms);
    public static native void openUrl(String url);
    public static native void exit();
    /** HuskPatch: Android's runtime permissions (husk.Permissions): what the user chose, and a request answered as input phase 11. */
    public static native int permissionState(String perm);
    public static native void requestPermissions(int id, String[] perms);
    /** HuskPatch: the iPhone's file picker (husk.Documents): copies into dest, answered as input phase 12, then collected; and a file handed to the iPhone (0 save to Files, 1 view, 2 share). */
    public static native void pickDocuments(int id, String mimes, int flags, String dest);
    public static native String documentResult(int id);
    public static native boolean exportDocument(String path, int mode);
    public static native long uptimeNanos();
}
