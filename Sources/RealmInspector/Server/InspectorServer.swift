import Foundation
import Network
import RealmSwift

/// The main server that coordinates connections, request handling, and change notifications
public final class InspectorServer {
    
    // MARK: - Properties
    
    private let realm: Realm
    private let advertiser: BonjourAdvertiser
    private let requestHandler: RequestHandler
    
    private var connections: Set<ClientConnection> = []
    private let connectionLock = NSLock()
    
    /// Realm notification tokens for live subscriptions
    private var notificationTokens: [String: NotificationToken] = [:]
    
    public private(set) var isRunning = false
    
    /// Called when server starts
    public var onStart: (() -> Void)?
    
    /// Called when server stops
    public var onStop: (() -> Void)?
    
    /// Called when a client connects
    public var onClientConnect: ((UUID) -> Void)?
    
    /// Called when a client disconnects
    public var onClientDisconnect: ((UUID) -> Void)?
    
    /// Called on error
    public var onError: ((Error) -> Void)?
    
    // MARK: - Initialization
    
    public init(realm: Realm, port: UInt16 = BonjourAdvertiser.defaultPort, serviceName: String? = nil) {
        self.realm = realm
        self.advertiser = BonjourAdvertiser(port: port, serviceName: serviceName)
        self.requestHandler = RequestHandler(realm: realm)
        
        setupAdvertiserCallbacks()
    }
    
    // MARK: - Server Lifecycle
    
    /// Start the inspector server
    public func start() throws {
        guard !isRunning else { return }
        
        try advertiser.startAdvertising()
        isRunning = true
        
        Logger.log("RealmInspector server started")
        onStart?()
    }
    
    /// Stop the inspector server
    public func stop() {
        guard isRunning else { return }
        
        // Close all connections
        connectionLock.lock()
        connections.forEach { $0.close() }
        connections.removeAll()
        connectionLock.unlock()
        
        // Cancel all subscriptions
        notificationTokens.values.forEach { $0.invalidate() }
        notificationTokens.removeAll()
        
        // Stop advertising
        advertiser.stopAdvertising()
        
        isRunning = false
        
        Logger.log("RealmInspector server stopped")
        onStop?()
    }
    
    // MARK: - Private Methods
    
    private func setupAdvertiserCallbacks() {
        advertiser.onConnection = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        advertiser.onError = { [weak self] error in
            self?.onError?(error)
        }
        
        advertiser.onStateChange = { [weak self] isAdvertising in
            if !isAdvertising {
                self?.isRunning = false
            }
        }
    }
    
    private func handleNewConnection(_ networkConnection: NWConnection) {
        let client = ClientConnection(connection: networkConnection)
        
        client.onRequest = { [weak self, weak client] request in
            guard let self = self, let client = client else { return }
            self.handleRequest(request, from: client)
        }
        
        client.onDisconnect = { [weak self, weak client] in
            guard let self = self, let client = client else { return }
            self.removeClient(client)
        }
        
        client.onError = { [weak self] error in
            Logger.log("Client error: \(error)")
            self?.onError?(error)
        }
        
        // Add to connections
        connectionLock.lock()
        connections.insert(client)
        connectionLock.unlock()
        
        // Start handling
        client.start()
        
        onClientConnect?(client.id)
    }
    
    private func removeClient(_ client: ClientConnection) {
        connectionLock.lock()
        connections.remove(client)
        connectionLock.unlock()
        
        // Remove subscriptions for this client
        for subscriptionId in client.activeSubscriptions {
            cleanupSubscription(subscriptionId)
        }
        
        onClientDisconnect?(client.id)
    }
    
    private func handleRequest(_ request: InspectorRequest, from client: ClientConnection) {
        // Special handling for subscription requests
        switch request.type {
        case .subscribe:
            handleSubscribe(request, from: client)
            return
            
        case .unsubscribe:
            handleUnsubscribe(request, from: client)
            return
            
        default:
            break
        }
        
        // Normal request handling
        requestHandler.handle(request) { [weak client] response in
            client?.send(response)
        }
    }
    
    // MARK: - Subscriptions
    
    private func handleSubscribe(_ request: InspectorRequest, from client: ClientConnection) {
        guard let typeName = request.params?["typeName"]?.value as? String else {
            client.send(.failure(id: request.id, error: "Missing typeName parameter"))
            return
        }
        
        let filter = request.params?["filter"]?.value as? String
        let subscriptionId = UUID().uuidString
        
        // Create Realm notification
        setupRealmNotification(
            subscriptionId: subscriptionId,
            typeName: typeName,
            filter: filter,
            client: client
        )
        
        // Add to client subscriptions
        client.addSubscription(subscriptionId)
        
        // Send success response
        client.send(.success(id: request.id, data: AnyCodable([
            "subscriptionId": subscriptionId,
            "typeName": typeName
        ])))
    }
    
    private func handleUnsubscribe(_ request: InspectorRequest, from client: ClientConnection) {
        guard let subscriptionId = request.params?["subscriptionId"]?.value as? String else {
            client.send(.failure(id: request.id, error: "Missing subscriptionId parameter"))
            return
        }
        
        client.removeSubscription(subscriptionId)
        cleanupSubscription(subscriptionId)
        
        client.send(.success(id: request.id, data: AnyCodable(["unsubscribed": true])))
    }
    
    private func setupRealmNotification(subscriptionId: String, typeName: String, filter: String?, client: ClientConnection) {
        var results = realm.dynamicObjects(typeName)
        
        if let filter = filter, !filter.isEmpty {
            let predicate = NSPredicate(format: filter)
            results = results.filter(predicate)
        }
        
        let serializer = ObjectSerializer()
        
        let token = results.observe { [weak self, weak client] changes in
            guard let self = self, let client = client else { return }
            
            switch changes {
            case .initial:
                // Don't send initial state - client can query if needed
                break
                
            case .update(let results, let deletions, let insertions, let modifications):
                let changeSet = self.buildChangeSet(
                    results: results,
                    deletions: deletions,
                    insertions: insertions,
                    modifications: modifications,
                    serializer: serializer
                )
                
                if !changeSet.isEmpty {
                    let notification = ChangeNotification(
                        subscriptionId: subscriptionId,
                        typeName: typeName,
                        changes: changeSet
                    )
                    client.send(notification)
                }
                
            case .error(let error):
                Logger.log("Subscription error: \(error)")
            }
        }
        
        notificationTokens[subscriptionId] = token
    }
    
    private func buildChangeSet(
        results: Results<DynamicObject>,
        deletions: [Int],
        insertions: [Int],
        modifications: [Int],
        serializer: ObjectSerializer
    ) -> ChangeSet {
        // Serialize insertions
        let insertedDocs = insertions.compactMap { index -> AnyCodable? in
            guard index < results.count else { return nil }
            return AnyCodable(serializer.serialize(results[index]))
        }
        
        // Serialize modifications
        let modifiedDocs = modifications.compactMap { index -> AnyCodable? in
            guard index < results.count else { return nil }
            return AnyCodable(serializer.serialize(results[index]))
        }
        
        // For deletions, we can't get the objects anymore, so we just return indices
        // In a real implementation, you'd want to track primary keys before deletion
        let deletedKeys = deletions.map { String($0) }
        
        return ChangeSet(
            insertions: insertedDocs,
            modifications: modifiedDocs,
            deletions: deletedKeys
        )
    }
    
    private func cleanupSubscription(_ subscriptionId: String) {
        if let token = notificationTokens.removeValue(forKey: subscriptionId) {
            token.invalidate()
        }
    }
    
    // MARK: - Stats
    
    /// Number of connected clients
    public var clientCount: Int {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        return connections.count
    }
    
    /// Number of active subscriptions
    public var subscriptionCount: Int {
        notificationTokens.count
    }
}

// MARK: - Convenience Factory

extension InspectorServer {
    
    /// Create a server with the default Realm
    public static func withDefaultRealm(port: UInt16 = BonjourAdvertiser.defaultPort) throws -> InspectorServer {
        let realm = try Realm()
        return InspectorServer(realm: realm, port: port)
    }
    
    /// Create a server with a Realm at a specific path
    public static func withRealm(at url: URL, port: UInt16 = BonjourAdvertiser.defaultPort) throws -> InspectorServer {
        var config = Realm.Configuration.defaultConfiguration
        config.fileURL = url
        let realm = try Realm(configuration: config)
        return InspectorServer(realm: realm, port: port)
    }
}
