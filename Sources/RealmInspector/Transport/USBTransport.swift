//
//  USBTransport.swift
//  RealmInspector
//
//  Created by Obe on 12/12/25.
//

import Foundation
import Network

/// USB Transport for RealmInspector using Network.framework device link
/// This allows connection from macOS over USB cable
public final class USBTransport {
    
    // MARK: - Configuration
    
    /// The port to listen on for USB connections (via usbmuxd)
    public static let defaultPort: UInt16 = 9877
    
    // MARK: - Properties
    
    private var listener: NWListener?
    public let port: UInt16
    
    public private(set) var isListening = false
    
    /// Called when a new connection is received
    public var onConnection: ((NWConnection) -> Void)?
    
    /// Called when an error occurs
    public var onError: ((Error) -> Void)?
    
    /// Called when listening state changes
    public var onStateChange: ((Bool) -> Void)?
    
    // MARK: - Initialization
    
    public init(port: UInt16 = USBTransport.defaultPort) {
        self.port = port
    }
    
    // MARK: - Listening
    
    /// Start listening for USB connections
    public func startListening() throws {
        guard !isListening else { return }
        
        // Create TCP parameters - usbmuxd forwards TCP connections
        let parameters = NWParameters.tcp
        
        // Create listener
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw USBTransportError.invalidPort
        }
        
        listener = try NWListener(using: parameters, on: nwPort)
        
        listener?.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener?.start(queue: .global(qos: .userInitiated))
        
        Logger.log("USB transport listening on port \(port)")
    }
    
    /// Stop listening
    public func stopListening() {
        listener?.cancel()
        listener = nil
        isListening = false
        onStateChange?(false)
        
        Logger.log("USB transport stopped")
    }
    
    // MARK: - Private Methods
    
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isListening = true
            onStateChange?(true)
            Logger.log("USB transport ready on port \(port)")
            
        case .failed(let error):
            isListening = false
            onError?(error)
            onStateChange?(false)
            Logger.log("USB transport failed: \(error)")
            
        case .cancelled:
            isListening = false
            onStateChange?(false)
            
        default:
            break
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        // Check if this looks like a local/USB connection
        Logger.log("USB transport received connection: \(connection.endpoint)")
        onConnection?(connection)
    }
}

// MARK: - Errors

public enum USBTransportError: Error, LocalizedError {
    case invalidPort
    case listenerFailed(Error)
    case notListening
    
    public var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "Invalid port number"
        case .listenerFailed(let error):
            return "Listener failed: \(error.localizedDescription)"
        case .notListening:
            return "USB transport is not listening"
        }
    }
}

