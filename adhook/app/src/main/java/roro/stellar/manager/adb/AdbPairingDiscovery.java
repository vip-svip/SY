package roro.stellar.manager.adb;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.os.Looper;

import java.net.InetAddress;
import java.util.ArrayDeque;
import java.util.HashSet;
import java.util.Set;

/**
 * Discovers Android Wireless Debugging pairing endpoints over DNS-SD.
 * Resolves one result at a time for compatibility with older NsdManager stacks.
 */
public final class AdbPairingDiscovery implements AutoCloseable {
    public static final String SERVICE_TYPE = "_adb-tls-pairing._tcp.";
    public static final String CONNECT_SERVICE_TYPE = "_adb-tls-connect._tcp.";
    private static final int MAX_DISCOVERED_SERVICES = 64;

    public interface Listener {
        void onStarted();
        void onDeviceFound(Device device);
        void onDeviceLost(String serviceName);
        void onError(String message, int errorCode);
        void onStopped();
    }

    public static final class Device {
        public final String serviceName;
        public final String host;
        public final int port;

        Device(String serviceName, String host, int port) {
            this.serviceName = serviceName;
            this.host = host;
            this.port = port;
        }

        @Override public String toString() {
            return serviceName + " · " + host + ":" + port;
        }
    }

    private final NsdManager manager;
    private final WifiManager wifiManager;
    private final Listener listener;
    private WifiManager.MulticastLock multicastLock;
    private final String serviceType;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ArrayDeque<NsdServiceInfo> resolveQueue = new ArrayDeque<>();
    private final Set<String> knownNames = new HashSet<>();
    private final Set<String> resolvedNames = new HashSet<>();
    private NsdManager.DiscoveryListener discoveryListener;
    private boolean resolving;
    private boolean started;
    private boolean closed;

    public AdbPairingDiscovery(Context context, Listener listener) {
        this(context, SERVICE_TYPE, listener);
    }

    /** The same serialized resolver is shared by the original pairing and post-pairing connect services. */
    public AdbPairingDiscovery(Context context, String requestedServiceType, Listener listener) {
        if (context == null || listener == null || requestedServiceType == null) {
            throw new IllegalArgumentException("NSD context, service type and listener are required");
        }
        String normalized = requestedServiceType.endsWith(".")
                ? requestedServiceType : requestedServiceType + ".";
        if (!SERVICE_TYPE.equalsIgnoreCase(normalized)
                && !CONNECT_SERVICE_TYPE.equalsIgnoreCase(normalized)) {
            throw new IllegalArgumentException("Unsupported ADB DNS-SD service type");
        }
        Object service = context.getApplicationContext().getSystemService(Context.NSD_SERVICE);
        if (!(service instanceof NsdManager)) {
            throw new IllegalStateException("Android Network Service Discovery is unavailable");
        }
        manager = (NsdManager) service;
        Object wifi = context.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        wifiManager = wifi instanceof WifiManager ? (WifiManager) wifi : null;
        this.listener = listener;
        this.serviceType = normalized;
    }

    public synchronized void start() {
        if (closed) throw new IllegalStateException("ADB pairing discovery is closed");
        if (started) return;
        started = true;
        discoveryListener = new NsdManager.DiscoveryListener() {
            @Override public void onStartDiscoveryFailed(String serviceType, int errorCode) {
                WifiManager.MulticastLock lock;
                synchronized (AdbPairingDiscovery.this) {
                    started = false;
                    lock = takeMulticastLockLocked();
                }
                releaseMulticastLock(lock);
                fail("无法启动 ADB 无线配对服务发现", errorCode);
            }

            @Override public void onStopDiscoveryFailed(String serviceType, int errorCode) {
                fail("无法停止 ADB 无线配对服务发现", errorCode);
            }

            @Override public void onDiscoveryStarted(String serviceType) {
                post(() -> listener.onStarted());
            }

            @Override public void onDiscoveryStopped(String serviceType) {
                WifiManager.MulticastLock lock;
                synchronized (AdbPairingDiscovery.this) {
                    started = false;
                    lock = takeMulticastLockLocked();
                }
                releaseMulticastLock(lock);
                post(() -> listener.onStopped());
            }

            @Override public void onServiceFound(NsdServiceInfo serviceInfo) {
                if (serviceInfo == null || !isExpectedService(serviceInfo.getServiceType())) return;
                String name = serviceInfo.getServiceName();
                if (name == null || name.isEmpty()) return;
                boolean overLimit = false;
                synchronized (AdbPairingDiscovery.this) {
                    if (closed || knownNames.contains(name)) return;
                    if (knownNames.size() >= MAX_DISCOVERED_SERVICES) {
                        overLimit = true;
                    } else {
                        knownNames.add(name);
                        resolveQueue.addLast(serviceInfo);
                    }
                }
                if (overLimit) {
                    post(() -> listener.onError(
                            "ADB DNS-SD 服务数量超过安全上限（" + MAX_DISCOVERED_SERVICES
                                    + "），已忽略后续广播", 1001));
                    return;
                }
                resolveNext();
            }

            @Override public void onServiceLost(NsdServiceInfo serviceInfo) {
                if (serviceInfo == null) return;
                String name = serviceInfo.getServiceName();
                if (name == null || name.isEmpty()) return;
                synchronized (AdbPairingDiscovery.this) {
                    knownNames.remove(name);
                    resolvedNames.remove(name);
                    resolveQueue.removeIf(pending ->
                            pending != null && name.equals(pending.getServiceName()));
                }
                post(() -> listener.onDeviceLost(name));
            }
        };
        try {
            acquireMulticastLock();
            manager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, discoveryListener);
        } catch (RuntimeException failure) {
            WifiManager.MulticastLock lock;
            synchronized (this) {
                started = false;
                lock = takeMulticastLockLocked();
            }
            releaseMulticastLock(lock);
            fail("ADB 无线配对服务发现启动失败：" + failure.getClass().getSimpleName(), -1);
        }
    }

    /** Hold Wi-Fi multicast reception only while this mDNS browse is active. */
    private synchronized void acquireMulticastLock() {
        if (wifiManager == null || multicastLock != null) return;
        WifiManager.MulticastLock lock = wifiManager.createMulticastLock("fx-adb-mdns-discovery");
        lock.setReferenceCounted(false);
        lock.acquire();
        multicastLock = lock;
    }

    private WifiManager.MulticastLock takeMulticastLockLocked() {
        WifiManager.MulticastLock lock = multicastLock;
        multicastLock = null;
        return lock;
    }

    private static void releaseMulticastLock(WifiManager.MulticastLock lock) {
        if (lock != null && lock.isHeld()) {
            try { lock.release(); } catch (RuntimeException ignored) { }
        }
    }

    private boolean isExpectedService(String type) {
        if (type == null) return false;
        String normalized = type.endsWith(".") ? type : type + ".";
        return serviceType.equalsIgnoreCase(normalized);
    }

    private void resolveNext() {
        final NsdServiceInfo next;
        synchronized (this) {
            if (closed || !started || resolving) return;
            while (!resolveQueue.isEmpty()) {
                NsdServiceInfo candidate = resolveQueue.peekFirst();
                if (candidate != null && knownNames.contains(candidate.getServiceName())) break;
                resolveQueue.removeFirst();
            }
            if (resolveQueue.isEmpty()) return;
            next = resolveQueue.removeFirst();
            resolving = true;
        }
        try {
            manager.resolveService(next, new NsdManager.ResolveListener() {
                @Override public void onResolveFailed(NsdServiceInfo serviceInfo, int errorCode) {
                    synchronized (AdbPairingDiscovery.this) {
                        resolving = false;
                        if (serviceInfo != null) knownNames.remove(serviceInfo.getServiceName());
                    }
                    post(() -> listener.onError("解析 ADB 配对服务失败", errorCode));
                    resolveNext();
                }

                @Override public void onServiceResolved(NsdServiceInfo serviceInfo) {
                    Device device = null;
                    if (serviceInfo != null) {
                        InetAddress address = serviceInfo.getHost();
                        int port = serviceInfo.getPort();
                        String name = serviceInfo.getServiceName();
                        if (address != null && port > 0 && port <= 65535) {
                            device = new Device(name, address.getHostAddress(), port);
                        }
                    }
                    boolean stillAdvertised = false;
                    synchronized (AdbPairingDiscovery.this) {
                        resolving = false;
                        if (device != null && !closed
                                && knownNames.contains(device.serviceName)) {
                            resolvedNames.add(device.serviceName);
                            stillAdvertised = true;
                        }
                    }
                    if (stillAdvertised) {
                        Device resolved = device;
                        post(() -> {
                            synchronized (AdbPairingDiscovery.this) {
                                if (closed || !resolvedNames.contains(resolved.serviceName)) return;
                            }
                            listener.onDeviceFound(resolved);
                        });
                    }
                    resolveNext();
                }
            });
        } catch (RuntimeException failure) {
            synchronized (this) {
                resolving = false;
                knownNames.remove(next.getServiceName());
            }
            post(() -> listener.onError(
                    "ADB 配对服务解析异常：" + failure.getClass().getSimpleName(), -1));
            resolveNext();
        }
    }

    private void fail(String message, int errorCode) {
        post(() -> listener.onError(message, errorCode));
    }

    private void post(Runnable action) {
        main.post(() -> {
            synchronized (AdbPairingDiscovery.this) {
                if (closed) return;
            }
            action.run();
        });
    }

    @Override
    public void close() {
        NsdManager.DiscoveryListener current;
        WifiManager.MulticastLock lock;
        synchronized (this) {
            if (closed) return;
            closed = true;
            current = discoveryListener;
            discoveryListener = null;
            started = false;
            resolving = false;
            resolveQueue.clear();
            knownNames.clear();
            resolvedNames.clear();
            lock = takeMulticastLockLocked();
        }
        if (current != null) {
            try {
                manager.stopServiceDiscovery(current);
            } catch (RuntimeException ignored) {
                // Discovery may have failed before NsdManager registered its listener.
            }
        }
        releaseMulticastLock(lock);
    }
}
