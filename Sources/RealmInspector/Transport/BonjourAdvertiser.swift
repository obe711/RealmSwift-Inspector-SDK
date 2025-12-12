import Foundation
import Network

/// Advertises the RealmInspector service via Bonjour for discovery by desktop clients
public final class BonjourAdvertiser: NSObject {
    
    // MARK: - Service Configuration
    
    /// The Bonjour service type for RealmInspector
    public static let serviceType = "_realminspector._tcp"
    
    /// Default port for the service
    public static let defaultPort: UInt16 = 9876
    
    // MARK: - Properties
    
    private var listener: NWListener?
    private var netService: NetService?
    
    private let port: UInt16
    private let serviceName: String
    
    public private(set) var isAdvertising = false
    
    /// Called when a new connection is received
    public var onConnection: ((NWConnection) -> Void)?
    
    /// Called when an error occurs
    public var onError: ((Error) -> Void)?
    
    /// Called when advertising state changes
    public var onStateChange: ((Bool) -> Void)?
    
    // MARK: - Initialization
    
    public init(port: UInt16 = BonjourAdvertiser.defaultPort, serviceName: String? = nil) {
        self.port = port
        self.serviceName = serviceName ?? Self.defaultServiceName()
        super.init()
    }
    
    // MARK: - Advertising
    
    /// Start advertising the service
    public func startAdvertising() throws {
        guard !isAdvertising else { return }
        
        // Create NWListener on the specified port
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        
        // Allow TLS to be optional for local development
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveInterval = 30
        
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        
        listener?.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        // Start the listener
        listener?.start(queue: .global(qos: .userInitiated))
        
        // Advertise via Bonjour
        advertiseService()
    }
    
    /// Stop advertising the service
    public func stopAdvertising() {
        guard isAdvertising else { return }
        
        listener?.cancel()
        listener = nil
        
        netService?.stop()
        netService = nil
        
        isAdvertising = false
        onStateChange?(false)
        
        Logger.log("Stopped advertising RealmInspector service")
    }
    
    // MARK: - Private Methods
    
    private func advertiseService() {
        // Create NetService for Bonjour advertisement
        netService = NetService(
            domain: "local.",
            type: Self.serviceType,
            name: serviceName,
            port: Int32(port)
        )
        
        // Add TXT record with metadata
        let txtRecord = createTXTRecord()
        netService?.setTXTRecord(NetService.data(fromTXTRecord: txtRecord))
        
        netService?.delegate = self
        netService?.publish()
    }
    
    private func createTXTRecord() -> [String: Data] {
        var record: [String: Data] = [:]
        
        // Add device info
        record["device"] = deviceName().data(using: .utf8)
        record["version"] = "1.0".data(using: .utf8)
        record["platform"] = platformName().data(using: .utf8)
        
        return record
    }
    
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isAdvertising = true
            onStateChange?(true)
            Logger.log("RealmInspector listening on port \(port)")
            
        case .failed(let error):
            isAdvertising = false
            onError?(error)
            onStateChange?(false)
            Logger.log("Listener failed: \(error)")
            
        case .cancelled:
            isAdvertising = false
            onStateChange?(false)
            
        default:
            break
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        Logger.log("New connection from: \(connection.endpoint)")
        onConnection?(connection)
    }
    
    // MARK: - Helpers
    
    private static func defaultServiceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "RealmInspector"
        #endif
    }
    
    private func deviceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Unknown"
        #endif
    }
    
    private func platformName() -> String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "Unknown"
        #endif
    }
}

// MARK: - NetServiceDelegate

extension BonjourAdvertiser: NetServiceDelegate {
    
    public func netServiceDidPublish(_ sender: NetService) {
        Logger.log("Published Bonjour service: \(sender.name)")
    }
    
    public func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        let errorCode = errorDict[NetService.errorCode]?.intValue ?? -1
        Logger.log("Failed to publish Bonjour service. Error code: \(errorCode)")
        onError?(BonjourError.publishFailed(errorCode))
    }
    
    public func netServiceDidStop(_ sender: NetService) {
        Logger.log("Bonjour service stopped")
    }
}

// MARK: - Errors

public enum BonjourError: Error, LocalizedError {
    case publishFailed(Int)
    case listenerFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .publishFailed(let code):
            return "Failed to publish Bonjour service (error code: \(code))"
        case .listenerFailed(let error):
            return "Network listener failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Logger

/// Simple logging utility for RealmInspector
enum Logger {
    static var isEnabled = true
    
    static func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard isEnabled else { return }
        
        let filename = URL(fileURLWithPath: file).lastPathComponent
        print("[RealmInspector] \(filename):\(line) - \(message)")
    }
}

// MARK: - iOS Import

#if os(iOS)
import UIKit
#endif
