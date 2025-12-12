//
//  ChangeNotifier.swift
//  RealmInspector
//
//  Observes Realm changes and broadcasts notifications to connected clients
//

import Foundation
import RealmSwift

/// Manages subscriptions to Realm changes
final class ChangeNotifier {
    
    // MARK: - Types
    
    struct Subscription {
        let id: String
        let typeName: String
        let filter: String?
        let realm: Realm
        let token: NotificationToken
    }
    
    // MARK: - Properties
    
    private var subscriptions: [String: Subscription] = [:]
    private let lock = NSLock()
    private let serializer: ObjectSerializer
    
    /// Called when a change notification should be broadcast
    var onNotification: ((ChangeNotification) -> Void)?
    
    // MARK: - Initialization
    
    init(serializer: ObjectSerializer) {
        self.serializer = serializer
    }
    
    deinit {
        unsubscribeAll()
    }
    
    // MARK: - Subscription Management
    
    /// Subscribe to changes for a type
    func subscribe(
        realm: Realm,
        typeName: String,
        filter: String?
    ) -> Result<String, Error> {
        
        let subscriptionId = UUID().uuidString
        
        // Get the results to observe
        var results = realm.dynamicObjects(typeName)
        
        if let filterString = filter, !filterString.isEmpty {
            do {
                results = results.filter(filterString)
            } catch {
                return .failure(error)
            }
        }
        
        // Create notification token
        let token = results.observe { [weak self] changes in
            self?.handleChanges(changes, subscriptionId: subscriptionId, typeName: typeName)
        }
        
        let subscription = Subscription(
            id: subscriptionId,
            typeName: typeName,
            filter: filter,
            realm: realm,
            token: token
        )
        
        lock.lock()
        subscriptions[subscriptionId] = subscription
        lock.unlock()
        
        return .success(subscriptionId)
    }
    
    /// Unsubscribe from changes
    func unsubscribe(id: String) {
        lock.lock()
        if let subscription = subscriptions.removeValue(forKey: id) {
            subscription.token.invalidate()
        }
        lock.unlock()
    }
    
    /// Unsubscribe from all changes
    func unsubscribeAll() {
        lock.lock()
        for (_, subscription) in subscriptions {
            subscription.token.invalidate()
        }
        subscriptions.removeAll()
        lock.unlock()
    }
    
    // MARK: - Change Handling
    
    private func handleChanges(_ changes: RealmCollectionChange<Results<DynamicObject>>, subscriptionId: String, typeName: String) {
        switch changes {
        case .initial:
            // Don't send notification for initial load
            break
            
        case .update(let results, let deletions, let insertions, let modifications):
            // Get the subscription to check if we need primary keys
            lock.lock()
            let subscription = subscriptions[subscriptionId]
            lock.unlock()
            
            guard let subscription = subscription else { return }
            
            // Serialize inserted objects
            var insertedDocuments: [AnyCodable] = []
            for index in insertions {
                if index < results.count {
                    let serializedObject = serializer.serialize(results[index])
                    insertedDocuments.append(AnyCodable(serializedObject))
                }
            }
            
            // Serialize modified objects  
            var modifiedDocuments: [AnyCodable] = []
            for index in modifications {
                if index < results.count {
                    let serializedObject = serializer.serialize(results[index])
                    modifiedDocuments.append(AnyCodable(serializedObject))
                }
            }
            
            // For deletions, we only have indices of deleted items since the objects are already gone
            // In Realm change notifications, deleted objects can't be accessed anymore
            // For now, we use indices as string identifiers - this may need to be enhanced
            // if primary keys are required for the desktop client
            let deletedKeys = deletions.map { "index_\($0)" }
            
            let changeSet = ChangeSet(
                insertions: insertedDocuments,
                modifications: modifiedDocuments, 
                deletions: deletedKeys
            )
            
            let notification = ChangeNotification(
                subscriptionId: subscriptionId,
                typeName: typeName,
                changes: changeSet
            )
            
            onNotification?(notification)
            
        case .error(let error):
            print("[RealmInspector] Subscription error: \(error)")
        }
    }
}

// MARK: - Subscription Info

extension ChangeNotifier {
    
    /// Get information about active subscriptions
    var activeSubscriptions: [(id: String, typeName: String)] {
        lock.lock()
        defer { lock.unlock() }
        return subscriptions.map { ($0.key, $0.value.typeName) }
    }
    
    /// Get count of active subscriptions
    var subscriptionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return subscriptions.count
    }
}
