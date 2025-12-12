import Foundation
import RealmSwift

/// Executes queries against Realm with support for filtering, sorting, and pagination
public final class QueryExecutor {
    
    private let realm: Realm
    private let serializer: ObjectSerializer
    
    public init(realm: Realm, serializer: ObjectSerializer = ObjectSerializer()) {
        self.realm = realm
        self.serializer = serializer
    }
    
    // MARK: - Query Execution
    
    /// Execute a query with the given parameters
    public func execute(_ params: QueryParams) throws -> QueryResult {
        guard realm.schema.objectSchema.contains(where: { $0.className == params.typeName }) else {
            throw QueryError.unknownType(params.typeName)
        }
        
        var results = realm.dynamicObjects(params.typeName)
        
        // Apply filter if provided
        if let filter = params.filter, !filter.isEmpty {
            do {
                results = try applyFilter(results, predicate: filter)
            } catch {
                throw QueryError.invalidPredicate(filter, error)
            }
        }
        
        // Apply sorting if provided
        if let sortKeyPath = params.sortKeyPath, !sortKeyPath.isEmpty {
            results = results.sorted(byKeyPath: sortKeyPath, ascending: params.ascending)
        }
        
        // Get total count before pagination
        let totalCount = results.count
        
        // Apply pagination
        let paginatedResults = applyPagination(results, skip: params.skip, limit: params.limit)
        
        // Serialize results
        let documents = paginatedResults.map { serializer.serialize($0) }
        
        return QueryResult(
            documents: documents,
            totalCount: totalCount,
            skip: params.skip,
            limit: params.limit,
            hasMore: params.skip + documents.count < totalCount
        )
    }
    
    /// Get a single document by primary key
    public func getDocument(typeName: String, primaryKey: Any) throws -> [String: Any]? {
        guard realm.schema.objectSchema.contains(where: { $0.className == typeName }) else {
            throw QueryError.unknownType(typeName)
        }
        
        // Try to find the object
        let object: DynamicObject?
        
        if let stringKey = primaryKey as? String {
            object = realm.dynamicObject(ofType: typeName, forPrimaryKey: stringKey)
        } else if let intKey = primaryKey as? Int {
            object = realm.dynamicObject(ofType: typeName, forPrimaryKey: intKey)
        } else if let objectIdString = primaryKey as? String,
                  let objectId = try? ObjectId(string: objectIdString) {
            object = realm.dynamicObject(ofType: typeName, forPrimaryKey: objectId)
        } else {
            throw QueryError.invalidPrimaryKey(primaryKey)
        }
        
        return object.map { serializer.serialize($0) }
    }
    
    /// Count documents matching a filter
    public func count(typeName: String, filter: String? = nil) throws -> Int {
        guard realm.schema.objectSchema.contains(where: { $0.className == typeName }) else {
            throw QueryError.unknownType(typeName)
        }
        
        var results = realm.dynamicObjects(typeName)
        
        if let filter = filter, !filter.isEmpty {
            results = try applyFilter(results, predicate: filter)
        }
        
        return results.count
    }
    
    // MARK: - Aggregations
    
    /// Get distinct values for a property
    public func distinct(typeName: String, propertyName: String) throws -> [Any] {
        guard realm.schema.objectSchema.contains(where: { $0.className == typeName }) else {
            throw QueryError.unknownType(typeName)
        }
        
        let results = realm.dynamicObjects(typeName).distinct(by: [propertyName])
        
        return results.compactMap { object -> Any? in
            return object[propertyName]
        }
    }
    
    // MARK: - Private Helpers
    
    private func applyFilter(_ results: Results<DynamicObject>, predicate: String) throws -> Results<DynamicObject> {
        // Parse the predicate string
        let nsPredicate = NSPredicate(format: predicate)
        return results.filter(nsPredicate)
    }
    
    private func applyPagination(_ results: Results<DynamicObject>, skip: Int, limit: Int) -> [DynamicObject] {
        let startIndex = min(skip, results.count)
        let endIndex = min(startIndex + limit, results.count)
        
        guard startIndex < endIndex else {
            return []
        }
        
        return Array(results[startIndex..<endIndex])
    }
}

// MARK: - Query Result

/// Result of a query execution
public struct QueryResult: Codable {
    public let documents: [[String: AnyCodable]]
    public let totalCount: Int
    public let skip: Int
    public let limit: Int
    public let hasMore: Bool
    
    public init(documents: [[String: Any]], totalCount: Int, skip: Int, limit: Int, hasMore: Bool) {
        self.documents = documents.map { dict in
            dict.mapValues { AnyCodable($0) }
        }
        self.totalCount = totalCount
        self.skip = skip
        self.limit = limit
        self.hasMore = hasMore
    }
}

// MARK: - Query Errors

public enum QueryError: Error, LocalizedError {
    case unknownType(String)
    case invalidPredicate(String, Error)
    case invalidPrimaryKey(Any)
    case propertyNotFound(String, String)
    
    public var errorDescription: String? {
        switch self {
        case .unknownType(let typeName):
            return "Unknown Realm type: \(typeName)"
        case .invalidPredicate(let predicate, let error):
            return "Invalid predicate '\(predicate)': \(error.localizedDescription)"
        case .invalidPrimaryKey(let key):
            return "Invalid primary key: \(key)"
        case .propertyNotFound(let property, let typeName):
            return "Property '\(property)' not found on type '\(typeName)'"
        }
    }
}

// MARK: - Mutation Support

extension QueryExecutor {
    
    /// Create a new document
    public func createDocument(typeName: String, data: [String: Any]) throws -> [String: Any] {
        guard realm.schema.objectSchema.contains(where: { $0.className == typeName }) else {
            throw QueryError.unknownType(typeName)
        }
        
        let object = realm.dynamicObject(ofType: typeName, forPrimaryKey: data["_id"] ?? data["id"])
        
        if object != nil {
            throw MutationError.documentAlreadyExists
        }
        
        var createdObject: DynamicObject!
        
        try realm.write {
            createdObject = realm.dynamicCreate(typeName, value: data, update: .error)
        }
        
        return serializer.serialize(createdObject)
    }
    
    /// Update an existing document
    public func updateDocument(typeName: String, primaryKey: Any, changes: [String: Any]) throws -> [String: Any] {
        guard let object = try findObject(typeName: typeName, primaryKey: primaryKey) else {
            throw MutationError.documentNotFound
        }
        
        try realm.write {
            for (key, value) in changes {
                // Skip type metadata
                guard !key.hasPrefix("_") else { continue }
                
                // Verify property exists
                guard object.objectSchema.properties.contains(where: { $0.name == key }) else {
                    throw QueryError.propertyNotFound(key, typeName)
                }
                
                object[key] = value
            }
        }
        
        return serializer.serialize(object)
    }
    
    /// Delete a document
    public func deleteDocument(typeName: String, primaryKey: Any) throws -> Bool {
        guard let object = try findObject(typeName: typeName, primaryKey: primaryKey) else {
            throw MutationError.documentNotFound
        }
        
        try realm.write {
            realm.delete(object)
        }
        
        return true
    }
    
    // MARK: - Private Mutation Helpers
    
    private func findObject(typeName: String, primaryKey: Any) throws -> DynamicObject? {
        if let stringKey = primaryKey as? String {
            // Could be a string key or ObjectId string
            if let objectId = try? ObjectId(string: stringKey) {
                return realm.dynamicObject(ofType: typeName, forPrimaryKey: objectId)
            }
            return realm.dynamicObject(ofType: typeName, forPrimaryKey: stringKey)
        } else if let intKey = primaryKey as? Int {
            return realm.dynamicObject(ofType: typeName, forPrimaryKey: intKey)
        }
        
        throw QueryError.invalidPrimaryKey(primaryKey)
    }
}

// MARK: - Mutation Errors

public enum MutationError: Error, LocalizedError {
    case documentNotFound
    case documentAlreadyExists
    case readOnlyRealm
    case writeFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .documentNotFound:
            return "Document not found"
        case .documentAlreadyExists:
            return "Document with this primary key already exists"
        case .readOnlyRealm:
            return "Cannot modify read-only Realm"
        case .writeFailed(let error):
            return "Write failed: \(error.localizedDescription)"
        }
    }
}
