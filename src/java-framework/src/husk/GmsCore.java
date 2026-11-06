package husk;

import android.content.Intent;
import android.os.Binder;
import android.os.IBinder;
import android.os.Parcel;
import android.os.RemoteException;

/** Google Play services' side of the connection, written from microG's open protocol definitions: none of Google's code is here.
 *  GooglePackages tells an app Play services is installed; this is what it then reaches. An app's Google libraries bind to
 *  Play services and ask its broker for an API by number. Each API Husk has no answer for is refused the way Play services refuses
 *  one it does not have (API_UNAVAILABLE), which the libraries handle, and logged by number, so the next API to write is known. */
public final class GmsCore {
    private GmsCore() {}
    static final String BROKER = "com.google.android.gms.common.internal.IGmsServiceBroker";
    static final String CALLBACKS = "com.google.android.gms.common.internal.IGmsCallbacks";
    static final String ADVERTISING_ID = "com.google.android.gms.ads.identifier.internal.IAdvertisingIdService";
    static final int GET_SERVICE = 46, ON_POST_INIT_COMPLETE = 1, API_UNAVAILABLE = 16;
    private static final int SAFE_PARCEL_MAGIC = 0x4f45, FIELD_SERVICE_ID = 2;
    /** Android's value for a user who opted out of ad personalisation: what this phone reports to every app. */
    private static final String NO_AD_ID = "00000000-0000-0000-0000-000000000000";

    /** How a callback leaves the broker's call: later, on the main thread. A test replaces it. */
    static java.util.function.Consumer<Runnable> sPost = r -> new android.os.Handler(android.os.Looper.getMainLooper()).post(r);

    /** What binding to this intent reaches, or null when it is not for Play services or has an interface of its own not written here. */
    public static IBinder bind(Intent i) {
        String pkg = i.getComponent() != null ? i.getComponent().getPackageName() : i.getPackage();
        String action = i.getAction();
        if (!GooglePackages.GMS.equals(pkg) || action == null) return null;
        if (action.startsWith("com.google.android.gms.ads.identifier.service.")) return new AdvertisingId();
        // these speak their own interface, not the broker's: refused as before
        if (action.startsWith("com.google.android.c2dm.") || action.startsWith("com.google.iid.")
                || action.equals("com.google.android.gms.measurement.START")) return null;
        log("connecting: " + action);
        return new Broker();
    }

    private static void log(String s) { android.util.Log.i("HuskGms", s); }

    /** The interface token at the start of every call, as Parcel.enforceInterface reads it. */
    private static boolean forInterface(Parcel data, String descriptor) {
        data.readInt(); data.readInt(); data.readInt();
        return descriptor.equals(data.readString());
    }

    /** GetServiceRequest is a SafeParcelable: a header, then fields that each say their number and size. */
    static int serviceId(Parcel data) {
        if (data.readInt() == 0) return -1;                      // no request
        int header = data.readInt();
        if ((header & 0xffff) != SAFE_PARCEL_MAGIC) return -1;
        int end = (header >>> 16) == 0xffff ? data.readInt() : header >>> 16;
        end += data.dataPosition();
        while (data.dataPosition() < end) {
            int field = data.readInt();
            int size = (field >>> 16) == 0xffff ? data.readInt() : field >>> 16;
            if ((field & 0xffff) == FIELD_SERVICE_ID) return data.readInt();
            data.setDataPosition(data.dataPosition() + size);
        }
        return -1;
    }

    static final class Broker extends Binder {
        Broker() { super(BROKER); }
        @Override protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) throws RemoteException {
            if (code >= LAST_CALL_TRANSACTION) return super.onTransact(code, data, reply, flags);
            if (!forInterface(data, BROKER)) { log("a call for another interface, code " + code); return false; }
            final IBinder callback = data.readStrongBinder();
            // Every method of the broker starts with the callback; only getService says which API by a number.
            int api = code == GET_SERVICE ? serviceId(data) : -1;
            log("API " + api + " (broker call " + code + ") is not written: answering API_UNAVAILABLE");
            if (reply != null) reply.writeNoException();
            if (callback != null) sPost.accept(() -> refuse(callback));
            return true;
        }
    }

    private static void refuse(IBinder callback) {
        Parcel data = Parcel.obtain();
        try {
            data.writeInterfaceToken(CALLBACKS);
            data.writeInt(API_UNAVAILABLE);
            data.writeStrongBinder(null);
            data.writeInt(0);                                    // no Bundle
            callback.transact(ON_POST_INIT_COMPLETE, data, null, IBinder.FLAG_ONEWAY);
        } catch (RemoteException e) {
            android.util.Log.w("HuskGms", "the app's callback failed", e);
        } finally { data.recycle(); }
    }

    /** IAdvertisingIdService, which ad and analytics libraries ask directly. */
    static final class AdvertisingId extends Binder {
        AdvertisingId() { super(ADVERTISING_ID); }
        @Override protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) throws RemoteException {
            if (code >= LAST_CALL_TRANSACTION) return super.onTransact(code, data, reply, flags);
            if (!forInterface(data, ADVERTISING_ID)) return false;
            if (code == 1) { reply.writeNoException(); reply.writeString(NO_AD_ID); return true; }    // getId
            if (code == 2) { reply.writeNoException(); reply.writeInt(1); return true; }              // isAdTrackingLimited
            if (code == 6) { reply.writeNoException(); reply.writeInt(0); return true; }              // isDebugLoggingEnabled
            return false;
        }
    }
}
