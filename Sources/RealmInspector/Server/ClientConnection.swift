import Foundation
import Network

/// Represents a connected client (desktop app)
public final class ClientConnection {
    
    // MARK: - Properties
    
    public let id: UUID
    public let connection: NWConnection
    public private(set) var isConnected = false
    
    private let coder = MessageCoder()
    private var streamBuffer: MessageCoder.StreamBuffer
    
    /// Called when a request is received
    public var onRequest: ((InspectorRequest) -> Void)?
    
    /// Called when the connection closes
    public var onDisconnect: (() -> Void)?
    
    /// Called on error
    public var onError: ((Error) -> Void)?
    
    // MARK: - Active Subscriptions
    
    private var subscriptions: Set<String> = []
    
    // MARK: - Initialization
    
    public init(connection: NWConnection) {
        self.id = UUID()
        self.connection = connection
        self.streamBuffer = coder.createStreamBuffer()
    }
    
    // MARK: - Connection Lifecycle
    
    /// Start handling the connection
    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleStateUpdate(state)
        }
        
        connection.start(queue: .global(qos: .userInitiated))
    }
    
    /// Close the connection
    public func close() {
        connection.cancel()
        isConnected = false
        subscriptions.removeAll()
    }
    
    // MARK: - Sending
    
    /// Send a response to the client
    public func send(_ response: InspectorResponse) {
        do {
            let data = try coder.encode(response)
            sendData(data)
        } catch {
            Logger.log("Failed to encode response: \(error)")
            onError?(error)
        }
    }
    
    /// Send a change notification to the client
    public func send(_ notification: ChangeNotification) {
        // Only send if client is subscribed
        guard subscriptions.contains(notification.subscriptionId) else {
            return
        }
        
        do {
            let data = try coder.encode(notification)
            sendData(data)
        } catch {
            Logger.log("Failed to encode notification: \(error)")
            onError?(error)
        }
    }
    
    private func sendData(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                Logger.log("Send error: \(error)")
                self?.onError?(error)
            }
        })
    }
    
    // MARK: - Subscriptions
    
    /// Add a subscription
    public func addSubscription(_ subscriptionId: String) {
        subscriptions.insert(subscriptionId)
    }
    
    /// Remove a subscription
    public func removeSubscription(_ subscriptionId: String) {
        subscriptions.remove(subscriptionId)
    }
    
    /// Check if client has a subscription
    public func hasSubscription(_ subscriptionId: String) -> Bool {
        subscriptions.contains(subscriptionId)
    }
    
    /// Get all active subscriptions
    public var activeSubscriptions: Set<String> {
        subscriptions
    }
    
    // MARK: - Private Methods
    
    private func handleStateUpdate(_ state: NWConnection.State) {
        switch state {
        case .ready:
            isConnected = true
            Logger.log("Client connected: \(id)")
            startReceiving()
            
        case .failed(let error):
            isConnected = false
            Logger.log("Client connection failed: \(error)")
            onError?(error)
            onDisconnect?()
            
        case .cancelled:
            isConnected = false
            Logger.log("Client disconnected: \(id)")
            onDisconnect?()
            
        default:
            break
        }
    }
    
    private func startReceiving() {
        receiveNextMessage()
    }
    
    private func receiveNextMessage() {
        guard isConnected else { return }
        
        // Receive data in chunks
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                Logger.log("Receive error: \(error)")
                self.onError?(error)
                return
            }
            
            if let data = content {
                self.handleReceivedData(data)
            }
            
            if isComplete {
                self.close()
            } else {
                self.receiveNextMessage()
            }
        }
    }
    
    private func handleReceivedData(_ data: Data) {
        streamBuffer.append(data)
        
        do {
            let messages = try streamBuffer.extractMessages()
            
            for message in messages {
                switch message {
                case .request(let request):
                    onRequest?(request)
                    
                case .response, .notification:
                    // We shouldn't receive these from clients
                    Logger.log("Unexpected message type received from client")
                }
            }
        } catch {
            Logger.log("Failed to decode messages: \(error)")
            onError?(error)
        }
    }
}

// MARK: - Hashable

extension ClientConnection: Hashable {
    public static func == (lhs: ClientConnection, rhs: ClientConnection) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - CustomStringConvertible

extension ClientConnection: CustomStringConvertible {
    public var description: String {
        "ClientConnection(id: \(id), connected: \(isConnected), subscriptions: \(subscriptions.count))"
    }
}
