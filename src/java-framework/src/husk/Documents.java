package husk;

import android.app.Activity;
import android.content.ClipData;
import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Intent;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;

/**
 * HuskPatch: an app's activities for files, answered by the iPhone. "Open a file" (ACTION_GET_CONTENT, ACTION_OPEN_DOCUMENT,
 * ACTION_PICK, the photo picker) and "open a folder" (ACTION_OPEN_DOCUMENT_TREE) show the iPhone's own picker; what the user
 * picks is copied into the app's storage (Download/, Pictures/, Movies/ of its sdcard) and handed back as the document a
 * phone's Files app would hand back: content://com.android.externalstorage.documents/document/primary:Download/name, which
 * the app opens, queries for its name and size, and lists (a folder) through the provider here.
 * The other way: a document the app creates (ACTION_CREATE_DOCUMENT) is saved to Files once the app has written it, and a file
 * it opens (ACTION_VIEW) or shares (ACTION_SEND with EXTRA_STREAM) goes to the iPhone's viewer or share sheet.
 * The host's answer comes back through the input queue (phase 12) to deliver(), on the main thread.
 */
public final class Documents {
    private Documents() {}

    public static final String AUTHORITY = "com.android.externalstorage.documents", ROOT = "primary";
    static final int MULTIPLE = 1, FOLDER = 2, MEDIA = 4;
    static final int SAVE = 0, VIEW = 1, SHARE = 2;

    private static final HashMap<Integer, Object[]> sPending = new HashMap<>();
    private static final HashSet<String> sToSave = new HashSet<>();
    private static int sNext = 1;

    // ---- the activities

    /** An activity no app here handles: true when it is one of these, answered (later) as a phone would. */
    static boolean start(Activity caller, Intent i, int request) {
        String action = i.getAction();
        if (action == null) return false;
        switch (action) {
        case Intent.ACTION_GET_CONTENT: case Intent.ACTION_OPEN_DOCUMENT: case Intent.ACTION_PICK:
        case "android.provider.action.PICK_IMAGES": {
            if (Intent.ACTION_PICK.equals(action) && !pickable(i)) return false;
            String[] mimes = mimes(i);
            int flags = i.getBooleanExtra(Intent.EXTRA_ALLOW_MULTIPLE, false) || i.getIntExtra("android.provider.extra.PICK_IMAGES_MAX", 1) > 1 ? MULTIPLE : 0;
            if (media(mimes) || "android.provider.action.PICK_IMAGES".equals(action)) flags |= MEDIA;
            pick(caller, request, mimes, flags, destination(mimes));
            return true;
        }
        case Intent.ACTION_OPEN_DOCUMENT_TREE:
            pick(caller, request, new String[0], FOLDER, Native.externalDir());
            return true;
        case Intent.ACTION_CREATE_DOCUMENT: {
            String name = i.getStringExtra(Intent.EXTRA_TITLE);
            if (name == null || name.isEmpty()) name = "Untitled" + extensionFor(i.getType());
            File dir = new File(Native.externalDir(), "Download");
            dir.mkdirs();
            File f = unique(dir, sanitize(name));
            try { f.createNewFile(); } catch (java.io.IOException e) { android.util.Log.e("Husk", "creating " + f + " failed", e); }
            synchronized (sToSave) { sToSave.add(f.getAbsolutePath()); }
            Intent data = new Intent();
            data.setData(uriFor(f));
            data.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            answer(caller, request, Activity.RESULT_OK, data);
            return true;
        }
        case Intent.ACTION_VIEW: {
            File f = local(i.getData());
            if (f == null || !f.isFile()) return false;
            if (!export(f, VIEW)) throw new android.content.ActivityNotFoundException("No Activity found to handle " + i);
            return true;
        }
        case Intent.ACTION_SEND: case Intent.ACTION_SEND_MULTIPLE: {
            ArrayList<Uri> streams = new ArrayList<>();
            Object one = i.getExtras() != null ? i.getExtras().get(Intent.EXTRA_STREAM) : null;
            if (one instanceof Uri) streams.add((Uri) one);
            else if (one instanceof List) for (Object o : (List<?>) one) if (o instanceof Uri) streams.add((Uri) o);
            ClipData clip = i.getClipData();
            if (streams.isEmpty() && clip != null) for (int k = 0; k < clip.getItemCount(); k++) if (clip.getItemAt(k).getUri() != null) streams.add(clip.getItemAt(k).getUri());
            boolean any = false;
            for (Uri u : streams) { File f = local(u); if (f != null) any |= export(f, SHARE); }
            return any;
        }
        default: return false;
        }
    }

    /** ACTION_PICK of a media collection (or a type): a picker. A contact, a ringtone... is not a file, and not here. */
    private static boolean pickable(Intent i) {
        String t = i.getType();
        if (t != null && (t.startsWith("image/") || t.startsWith("video/") || t.startsWith("audio/") || t.startsWith("application/") || t.startsWith("text/"))) return true;
        Uri u = i.getData();
        return u != null && "media".equals(u.getAuthority());
    }

    private static String[] mimes(Intent i) {
        ArrayList<String> out = new ArrayList<>();
        String[] extra = i.getStringArrayExtra(Intent.EXTRA_MIME_TYPES);
        if (extra != null) for (String m : extra) if (m != null && !m.isEmpty()) out.add(m);
        if (out.isEmpty() && i.getType() != null) out.add(i.getType());
        Uri u = i.getData();
        if (out.isEmpty() && u != null && "media".equals(u.getAuthority())) {
            String p = u.getPath() == null ? "" : u.getPath();
            out.add(p.contains("/video") ? "video/*" : p.contains("/audio") ? "audio/*" : "image/*");
        }
        if (out.isEmpty()) {
            String max = i.getType();
            out.add(max != null ? max : "*/*");
        }
        return out.toArray(new String[0]);
    }

    private static boolean media(String[] mimes) {
        if (mimes.length == 0) return false;
        for (String m : mimes) if (!m.startsWith("image/") && !m.startsWith("video/")) return false;
        return true;
    }

    private static String destination(String[] mimes) {
        boolean images = true, videos = true;
        for (String m : mimes) { images &= m.startsWith("image/"); videos &= m.startsWith("video/"); }
        return new File(Native.externalDir(), images ? "Pictures" : videos ? "Movies" : "Download").getAbsolutePath();
    }

    private static void pick(Activity caller, int request, String[] mimes, int flags, String dest) {
        new File(dest).mkdirs();
        int id;
        synchronized (sPending) { id = sNext++; sPending.put(id, new Object[] { caller, request, flags }); }
        StringBuilder m = new StringBuilder();
        for (String s : mimes) { if (m.length() > 0) m.append('\n'); m.append(s); }
        try {
            Native.pickDocuments(id, m.toString(), flags, dest);
        } catch (Throwable t) {
            /* an older runtime without the picker: the user backed out, as far as the app can tell */
            synchronized (sPending) { sPending.remove(id); }
            answer(caller, request, Activity.RESULT_CANCELED, null);
        }
    }

    /** From the input queue: the picker closed; picked says the user chose something. */
    static void deliver(int id, boolean picked) {
        Object[] p;
        synchronized (sPending) { p = sPending.remove(id); }
        if (p == null) return;
        Activity caller = (Activity) p[0];
        int request = (Integer) p[1], flags = (Integer) p[2];
        String paths = picked ? Native.documentResult(id) : null;
        if (paths == null || paths.isEmpty()) { answer(caller, request, Activity.RESULT_CANCELED, null); return; }
        ArrayList<Uri> uris = new ArrayList<>();
        for (String s : paths.split("\n")) if (!s.isEmpty()) uris.add((flags & FOLDER) != 0 ? treeUriFor(new File(s)) : uriFor(new File(s)));
        if (uris.isEmpty()) { answer(caller, request, Activity.RESULT_CANCELED, null); return; }
        Intent data = new Intent();
        data.setData(uris.get(0));
        if ((flags & MULTIPLE) != 0) {
            ClipData clip = new ClipData("", new String[] { "*/*" }, new ClipData.Item(uris.get(0)));
            for (int k = 1; k < uris.size(); k++) clip.addItem(new ClipData.Item(uris.get(k)));
            data.setClipData(clip);
        }
        data.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION | 0x40 /* PERSISTABLE */);
        android.util.Log.d("Husk", "picked " + uris);
        answer(caller, request, Activity.RESULT_OK, data);
    }

    private static void answer(Activity caller, int request, int result, Intent data) {
        Activity a = caller != null ? caller : AppRunner.top();
        if (request < 0 || a == null) return;
        new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> a.huskActivityResult(request, result, data));
    }

    // ---- files handed to the iPhone

    private static boolean export(File f, int mode) {
        try { return Native.exportDocument(f.getAbsolutePath(), mode); } catch (Throwable t) { return false; }
    }

    /** A document from ACTION_CREATE_DOCUMENT, written and closed: saved to Files, once. */
    static void written(File f) {
        boolean save;
        synchronized (sToSave) { save = sToSave.remove(f.getAbsolutePath()); }
        if (save && f.length() > 0) export(f, SAVE);
        else if (save) synchronized (sToSave) { sToSave.add(f.getAbsolutePath()); }
    }

    /** The file a URI the app opens or shares is, when it is one of its own: file://, a document here, its own FileProvider's. */
    static File local(Uri u) {
        if (u == null) return null;
        String s = u.getScheme();
        if ("file".equals(s) || s == null) return u.getPath() != null ? new File(u.getPath()) : null;
        if (!"content".equals(s)) return null;
        if (AUTHORITY.equals(u.getAuthority())) { try { return file(documentId(u)); } catch (RuntimeException e) { return null; } }
        /* someone else's content (the app's FileProvider): copied out so the iPhone can read it */
        try (java.io.InputStream in = ContextImpl.app().getContentResolver().openInputStream(u)) {
            String name = displayName(u);
            File dir = new File(Native.dataDir(), "cache/husk-shared");
            dir.mkdirs();
            File out = new File(dir, sanitize(name));
            try (java.io.FileOutputStream o = new java.io.FileOutputStream(out)) {
                byte[] b = new byte[65536];
                for (int n; (n = in.read(b)) > 0; ) o.write(b, 0, n);
            }
            return out;
        } catch (Exception e) {
            android.util.Log.e("Husk", "reading " + u + " to hand it on failed", e);
            return null;
        }
    }

    private static String displayName(Uri u) {
        try (Cursor c = ContextImpl.app().getContentResolver().query(u, new String[] { "_display_name" }, null, null, null)) {
            if (c != null && c.moveToFirst() && c.getString(0) != null) return c.getString(0);
        } catch (Exception e) { /* a provider without the column */ }
        String last = u.getLastPathSegment();
        return last != null && !last.isEmpty() ? last : "file";
    }

    // ---- documents: content://com.android.externalstorage.documents/{document/ID | tree/ID[/document/ID][/children]}

    public static Uri uriFor(File f) { return android.provider.DocumentsContract.buildDocumentUri(AUTHORITY, idFor(f)); }
    public static Uri treeUriFor(File f) { return android.provider.DocumentsContract.buildTreeDocumentUri(AUTHORITY, idFor(f)); }

    public static String idFor(File f) {
        String root = new File(Native.externalDir()).getAbsolutePath(), p = f.getAbsolutePath();
        if (p.equals(root)) return ROOT + ":";
        if (p.startsWith(root + "/")) return ROOT + ":" + p.substring(root.length() + 1);
        return "raw:" + p;
    }

    public static File file(String id) {
        if (id == null) throw new IllegalArgumentException("no document id");
        if (id.startsWith("raw:")) return new File(id.substring(4));
        int c = id.indexOf(':');
        String rel = c >= 0 ? id.substring(c + 1) : id;
        File f = new File(Native.externalDir(), rel);
        String root = new File(Native.externalDir()).getAbsolutePath();
        try { if (!f.getCanonicalPath().startsWith(new File(root).getCanonicalPath())) throw new IllegalArgumentException("outside the storage: " + id); }
        catch (java.io.IOException e) { throw new IllegalArgumentException(e.toString()); }
        return f;
    }

    static String documentId(Uri u) {
        List<String> s = u.getPathSegments();
        if (s.size() >= 2 && "document".equals(s.get(0))) return s.get(1);
        if (s.size() >= 4 && "tree".equals(s.get(0)) && "document".equals(s.get(2))) return s.get(3);
        if (s.size() >= 2 && "tree".equals(s.get(0))) return s.get(1);
        throw new IllegalArgumentException("Invalid URI: " + u);
    }

    static String mimeOf(File f) {
        if (f.isDirectory()) return "vnd.android.document/directory";
        String n = f.getName().toLowerCase(java.util.Locale.ROOT);
        int dot = n.lastIndexOf('.');
        String ext = dot >= 0 ? n.substring(dot + 1) : "";
        String m = android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
        if (m == null) m = java.net.URLConnection.guessContentTypeFromName(n);
        return m != null ? m : "application/octet-stream";
    }

    private static String extensionFor(String mime) {
        if (mime == null) return "";
        String e = android.webkit.MimeTypeMap.getSingleton().getExtensionFromMimeType(mime);
        return e != null ? "." + e : "";
    }

    public static String sanitize(String name) {
        String n = name.replace('/', '_').replace('\0', '_').trim();
        return n.isEmpty() || n.equals(".") || n.equals("..") ? "file" : n;
    }

    public static File unique(File dir, String name) {
        File f = new File(dir, name);
        if (!f.exists()) return f;
        int dot = name.lastIndexOf('.');
        String base = dot > 0 ? name.substring(0, dot) : name, ext = dot > 0 ? name.substring(dot) : "";
        for (int k = 1; ; k++) { f = new File(dir, base + " (" + k + ")" + ext); if (!f.exists()) return f; }
    }

    private static final String[] DEFAULT_COLUMNS = { "document_id", "_display_name", "mime_type", "_size", "last_modified", "flags", "_data", "_id" };

    /** The documents provider: the app's sdcard, as Android's external storage provider shows it. */
    public static final class Provider extends ContentProvider {
        public static final Provider INSTANCE = new Provider();
        @Override public boolean onCreate() { return true; }

        @Override public Cursor query(Uri u, String[] proj, String sel, String[] args, String sort) {
            String[] cols = proj != null && proj.length > 0 ? proj : DEFAULT_COLUMNS;
            MatrixCursor c = new MatrixCursor(cols);
            File f;
            try { f = file(documentId(u)); } catch (IllegalArgumentException e) { return c; }
            List<String> seg = u.getPathSegments();
            if (!seg.isEmpty() && "children".equals(seg.get(seg.size() - 1))) {
                File[] kids = f.listFiles();
                if (kids != null) { java.util.Arrays.sort(kids); for (File k : kids) row(c, cols, k); }
            } else if (f.exists()) row(c, cols, f);
            return c;
        }

        private static void row(MatrixCursor c, String[] cols, File f) {
            Object[] r = new Object[cols.length];
            for (int k = 0; k < cols.length; k++) {
                switch (cols[k]) {
                case "document_id": r[k] = idFor(f); break;
                case "_display_name": case "title": r[k] = f.getName(); break;
                case "mime_type": r[k] = mimeOf(f); break;
                case "_size": r[k] = f.isDirectory() ? null : (Object) f.length(); break;
                case "last_modified": case "date_modified": r[k] = f.lastModified(); break;
                case "flags": r[k] = f.isDirectory() ? 8 | 4 | 64 /* create, delete, rename */ : 2 | 4 | 64 /* write, delete, rename */; break;
                case "_data": r[k] = f.getAbsolutePath(); break;
                case "_id": r[k] = (long) f.getAbsolutePath().hashCode(); break;
                default: r[k] = null;
                }
            }
            c.addRow(r);
        }

        @Override public String getType(Uri u) {
            try { return mimeOf(file(documentId(u))); } catch (IllegalArgumentException e) { return null; }
        }

        @Override public ParcelFileDescriptor openFile(Uri u, String mode) throws java.io.FileNotFoundException {
            final File f;
            try { f = file(documentId(u)); } catch (IllegalArgumentException e) { throw new java.io.FileNotFoundException(e.getMessage()); }
            if (mode == null) mode = "r";
            if (mode.contains("w") && f.getParentFile() != null) f.getParentFile().mkdirs();
            ParcelFileDescriptor pfd = ParcelFileDescriptor.open(f, ParcelFileDescriptor.parseMode(mode));
            if (!mode.contains("w")) return pfd;
            return new ParcelFileDescriptor(pfd) {
                @Override public void close() throws java.io.IOException { super.close(); written(f); }
            };
        }

        @Override public Uri insert(Uri u, ContentValues v) { return null; }

        @Override public int delete(Uri u, String sel, String[] args) {
            try { return deleteTree(file(documentId(u))) ? 1 : 0; } catch (IllegalArgumentException e) { return 0; }
        }

        @Override public int update(Uri u, ContentValues v, String sel, String[] args) { return 0; }

        static boolean deleteTree(File f) {
            File[] kids = f.isDirectory() ? f.listFiles() : null;
            if (kids != null) for (File k : kids) deleteTree(k);
            return f.delete();
        }
    }

    /** ContentResolver.openOutputStream on a document: its close saves a created document to Files. */
    public static java.io.OutputStream outputStream(Uri u, String mode) throws java.io.FileNotFoundException {
        final File f;
        try { f = file(documentId(u)); } catch (IllegalArgumentException e) { throw new java.io.FileNotFoundException(e.getMessage()); }
        if (f.getParentFile() != null) f.getParentFile().mkdirs();
        return new java.io.FileOutputStream(f, mode != null && mode.contains("a")) {
            private boolean closed;
            @Override public void close() throws java.io.IOException {
                super.close();
                if (!closed) { closed = true; written(f); }
            }
        };
    }
}
