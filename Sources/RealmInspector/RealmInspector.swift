import Foundation
import RealmSwift

/// RealmInspector - A development tool for inspecting Realm databases on iOS devices
///
/// Usage:
/// ```swift
/// #if DEBUG
/// import RealmInspector
///
/// // In your AppDelegate or SceneDelegate:
/// RealmInspector.shared.start()
///
/// // Or with a specific Realm:
/// RealmInspector.shared.start(realm: myRealm)
///
/// // For USB-only connection:
/// RealmInspector.shared.start(transportMode: .usbOnly)
/// ```
///
/// The desktop app will automatically discover your device on the network or USB.
public final class RealmInspector {
    
    // MARK: - Singleton
    
    /// Shared instance of RealmInspector
    public static let shared = RealmInspector()
    
    // MARK: - Properties
    
    private var server: InspectorServer?
    private var realm: Realm?
    
    /// Whether the inspector is currently running
    public var isRunning: Bool {
        server?.isRunning ?? false
    }
    
    /// Number of connected clients
    public var connectedClients: Int {
        server?.clientCount ?? 0
    }
    
    /// Network port the server is running on
    public private(set) var networkPort: UInt16 = BonjourAdvertiser.defaultPort
    
    /// USB port the server is running on
    public private(set) var usbPort: UInt16 = USBTransport.defaultPort
    
    /// Current transport mode
    public private(set) var transportMode: TransportMode = .both
    
    // MARK: - Callbacks
    
    /// Called when the inspector starts
    public var onStart: (() -> Void)?
    
    /// Called when the inspector stops
    public var onStop: (() -> Void)?
    
    /// Called when a client connects
    public var onClientConnect: ((UUID) -> Void)?
    
    /// Called when a client disconnects
    public var onClientDisconnect: ((UUID) -> Void)?
    
    /// Called on errors
    public var onError: ((Error) -> Void)?
    
    // MARK: - Initialization
    
    private init() {
        // Check if we should auto-disable in release builds
        #if !DEBUG
        Logger.log("⚠️ RealmInspector should only be used in DEBUG builds")
        #endif
    }
    
    // MARK: - Public API (Legacy/Simple)
    
    /// Start the inspector with the default Realm (legacy API)
    ///
    /// - Parameter port: Port to listen on (default: 9876)
    @discardableResult
    public func start(port: UInt16 = BonjourAdvertiser.defaultPort) -> Bool {
        return start(networkPort: port, transportMode: .both)
    }
    
    /// Start the inspector with a specific Realm instance (legacy API)
    ///
    /// - Parameters:
    ///   - realm: The Realm instance to inspect
    ///   - port: Port to listen on (default: 9876)
    @discardableResult
    public func start(realm: Realm, port: UInt16 = BonjourAdvertiser.defaultPort) -> Bool {
        return start(
            realm: realm,
            networkPort: port,
            usbPort: USBTransport.defaultPort,
            serviceName: nil,
            transportMode: .both
        )
    }
    
    /// Start the inspector with a Realm configuration (legacy API)
    ///
    /// - Parameters:
    ///   - configuration: Realm configuration to use
    ///   - port: Port to listen on (default: 9876)
    @discardableResult
    public func start(configuration: Realm.Configuration, port: UInt16 = BonjourAdvertiser.defaultPort) -> Bool {
        return start(
            configuration: configuration,
            networkPort: port,
            usbPort: USBTransport.defaultPort,
            serviceName: nil,
            transportMode: .both
        )
    }
    
    // MARK: - Public API (Full)
    
    /// Start the inspector with the default Realm
    ///
    /// - Parameters:
    ///   - networkPort: Port for network connections (default: 9876)
    ///   - usbPort: Port for USB connections (default: 9877)
    ///   - serviceName: Custom Bonjour service name (default: device name)
    ///   - transportMode: Which transports to enable (default: .both)
    @discardableResult
    public func start(
        networkPort: UInt16 = BonjourAdvertiser.defaultPort,
        usbPort: UInt16 = USBTransport.defaultPort,
        serviceName: String? = nil,
        transportMode: TransportMode = .both
    ) -> Bool {
        do {
            let realm = try Realm()
            return start(
                realm: realm,
                networkPort: networkPort,
                usbPort: usbPort,
                serviceName: serviceName,
                transportMode: transportMode
            )
        } catch {
            Logger.log("Failed to open default Realm: \(error)")
            onError?(error)
            return false
        }
    }
    
    /// Start the inspector with a specific Realm instance
    ///
    /// - Parameters:
    ///   - realm: The Realm instance to inspect
    ///   - networkPort: Port for network connections (default: 9876)
    ///   - usbPort: Port for USB connections (default: 9877)
    ///   - serviceName: Custom Bonjour service name (default: device name)
    ///   - transportMode: Which transports to enable (default: .both)
    @discardableResult
    public func start(
        realm: Realm,
        networkPort: UInt16 = BonjourAdvertiser.defaultPort,
        usbPort: UInt16 = USBTransport.defaultPort,
        serviceName: String? = nil,
        transportMode: TransportMode = .both
    ) -> Bool {
        // Stop any existing server
        stop()
        
        self.realm = realm
        self.networkPort = networkPort
        self.usbPort = usbPort
        self.transportMode = transportMode
        
        do {
            server = InspectorServer(
                realm: realm,
                networkPort: networkPort,
                usbPort: usbPort,
                serviceName: serviceName,
                transportMode: transportMode
            )
            setupServerCallbacks()
            try server?.start()
            
            Logger.log("✅ RealmInspector started (mode: \(transportMode))")
            printConnectionInfo()
            
            return true
        } catch {
            Logger.log("❌ Failed to start RealmInspector: \(error)")
            onError?(error)
            return false
        }
    }
    
    /// Start the inspector with a Realm configuration
    ///
    /// - Parameters:
    ///   - configuration: Realm configuration to use
    ///   - networkPort: Port for network connections (default: 9876)
    ///   - usbPort: Port for USB connections (default: 9877)
    ///   - serviceName: Custom Bonjour service name (default: device name)
    ///   - transportMode: Which transports to enable (default: .both)
    @discardableResult
    public func start(
        configuration: Realm.Configuration,
        networkPort: UInt16 = BonjourAdvertiser.defaultPort,
        usbPort: UInt16 = USBTransport.defaultPort,
        serviceName: String? = nil,
        transportMode: TransportMode = .both
    ) -> Bool {
        do {
            let realm = try Realm(configuration: configuration)
            return start(
                realm: realm,
                networkPort: networkPort,
                usbPort: usbPort,
                serviceName: serviceName,
                transportMode: transportMode
            )
        } catch {
            Logger.log("Failed to open Realm with configuration: \(error)")
            onError?(error)
            return false
        }
    }
    
    /// Stop the inspector
    public func stop() {
        server?.stop()
        server = nil
        realm = nil
        
        Logger.log("RealmInspector stopped")
    }
    
    /// Update the Realm instance being inspected
    ///
    /// Use this if you need to switch to a different Realm without restarting
    public func updateRealm(_ realm: Realm) {
        guard isRunning else {
            Logger.log("Cannot update Realm - inspector not running")
            return
        }
        
        let currentNetworkPort = self.networkPort
        let currentUsbPort = self.usbPort
        let currentTransportMode = self.transportMode
        stop()
        start(realm: realm, networkPort: currentNetworkPort, usbPort: currentUsbPort, transportMode: currentTransportMode)
    }
    
    // MARK: - Private Methods
    
    private func setupServerCallbacks() {
        server?.onStart = { [weak self] in
            self?.onStart?()
        }
        
        server?.onStop = { [weak self] in
            self?.onStop?()
        }
        
        server?.onClientConnect = { [weak self] clientId in
            Logger.log("📱 Client connected: \(clientId)")
            self?.onClientConnect?(clientId)
        }
        
        server?.onClientDisconnect = { [weak self] clientId in
            Logger.log("📱 Client disconnected: \(clientId)")
            self?.onClientDisconnect?(clientId)
        }
        
        server?.onError = { [weak self] error in
            self?.onError?(error)
        }
    }
    
    private func printConnectionInfo() {
        #if os(iOS)
        if let deviceName = UIDevice.current.name.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
            Logger.log("📡 Device: \(deviceName)")
        }
        #endif
        
        Logger.log("📡 Transport Mode: \(transportMode)")
        
        if transportMode == .networkOnly || transportMode == .both {
            Logger.log("📡 Network Service: \(BonjourAdvertiser.serviceType)")
            Logger.log("📡 Network Port: \(networkPort)")
        }
        
        if transportMode == .usbOnly || transportMode == .both {
            Logger.log("🔌 USB Port: \(usbPort)")
        }
        
        Logger.log("📡 Ready for connections from RealmCompass desktop app")
    }
}

// MARK: - Convenience Extensions

extension RealmInspector {
    
    /// Configure logging
    public func setLoggingEnabled(_ enabled: Bool) {
        Logger.isEnabled = enabled
    }
}

// MARK: - SwiftUI Support

#if canImport(SwiftUI)
import SwiftUI

/// A view modifier that starts RealmInspector when the view appears
@available(iOS 14.0, macOS 11.0, *)
public struct RealmInspectorModifier: ViewModifier {
    let realm: Realm?
    let port: UInt16
    
    public init(realm: Realm? = nil, port: UInt16 = BonjourAdvertiser.defaultPort) {
        self.realm = realm
        self.port = port
    }
    
    public func body(content: Content) -> some View {
        content
            .onAppear {
                #if DEBUG
                if let realm = realm {
                    RealmInspector.shared.start(realm: realm, port: port)
                } else {
                    RealmInspector.shared.start(port: port)
                }
                #endif
            }
            .onDisappear {
                #if DEBUG
                RealmInspector.shared.stop()
                #endif
            }
    }
}

@available(iOS 14.0, macOS 11.0, *)
extension View {
    /// Attach RealmInspector to this view's lifecycle
    ///
    /// The inspector will start when the view appears and stop when it disappears.
    ///
    /// - Parameters:
    ///   - realm: Optional specific Realm to inspect (uses default if nil)
    ///   - port: Port to listen on
    public func realmInspector(realm: Realm? = nil, port: UInt16 = BonjourAdvertiser.defaultPort) -> some View {
        modifier(RealmInspectorModifier(realm: realm, port: port))
    }
}
#endif

// MARK: - Status View (Debug UI)

#if os(iOS) && canImport(SwiftUI)
import SwiftUI

/// A small floating status indicator for RealmInspector
@available(iOS 14.0, *)
public struct RealmInspectorStatusView: View {
    @State private var isRunning = RealmInspector.shared.isRunning
    @State private var clientCount = RealmInspector.shared.connectedClients
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text("RI")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
            
            if isRunning && clientCount > 0 {
                Text("\(clientCount)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemBackground).opacity(0.9))
        .cornerRadius(12)
        .shadow(radius: 2)
        .onReceive(timer) { _ in
            isRunning = RealmInspector.shared.isRunning
            clientCount = RealmInspector.shared.connectedClients
        }
    }
}
#endif

// MARK: - iOS Import

#if os(iOS)
import UIKit
#endif
