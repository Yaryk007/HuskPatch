package android.security;

/* OkHttp and Glide ask it before every http:// request. Apps that need cleartext allow it in their manifest or network
   security config, which Husk does not read, so cleartext is always permitted. */
public class NetworkSecurityPolicy {
    private static final NetworkSecurityPolicy sInstance = new NetworkSecurityPolicy();
    private boolean mCleartext = true;

    protected NetworkSecurityPolicy() {}
    public static NetworkSecurityPolicy getInstance() { return sInstance; }
    public static android.security.net.config.ApplicationConfig getApplicationConfigForPackage(android.content.Context c, String pkg) { return null; }
    public boolean isCleartextTrafficPermitted() { return mCleartext; }
    public boolean isCleartextTrafficPermitted(String host) { return mCleartext; }
    public void setCleartextTrafficPermitted(boolean permitted) { mCleartext = permitted; }
    public boolean isCertificateTransparencyVerificationRequired(String host) { return false; }
    public void handleTrustStorageUpdate() {}
}
