import Foundation
import RealmSwift

/// Handles incoming requests from clients and produces responses
public final class RequestHandler {
    
    // MARK: - Properties
    
    private let realm: Realm
    private let schemaExtractor: SchemaExtractor
    private let serializer: ObjectSerializer
    private let queryExecutor: QueryExecutor
    
    /// Dedicated queue for Realm operations
    private let realmQueue = DispatchQueue(label: "com.realminspector.realm", qos: .userInitiated)
    
    // MARK: - Initialization
    
    public init(realm: Realm) {
        self.realm = realm
        self.schemaExtractor = SchemaExtractor(realm: realm)
        self.serializer = ObjectSerializer()
        self.queryExecutor = QueryExecutor(realm: realm, serializer: serializer)
    }
    
    // MARK: - Request Handling
    
    /// Handle a request and return a response
    public func handle(_ request: InspectorRequest, completion: @escaping (InspectorResponse) -> Void) {
        Logger.log("📨 Received request - ID: \(request.id), Type: \(request.type)")
        if let params = request.params {
            let paramsSummary = params.map { "\($0.key)=\(String(describing: $0.value.value))" }.joined(separator: ", ")
            Logger.log("   Parameters: \(paramsSummary)")
        }

        let startTime = Date()

        realmQueue.async { [weak self] in
            guard let self = self else {
                Logger.log("❌ Handler deallocated for request \(request.id)")
                completion(.failure(id: request.id, error: "Handler deallocated"))
                return
            }

            Logger.log("⚙️  Processing request \(request.id) on realmQueue")

            DispatchQueue.main.async {
                let response = self.processRequest(request)
                let duration = Date().timeIntervalSince(startTime)

                if response.success {
                    Logger.log("✅ Request \(response.id) succeeded in \(String(format: "%.3f", duration))s")
                    if let data = response.data {
                        Logger.log("   Response data type: \(type(of: data.value))")
                    }
                } else {
                    Logger.log("❌ Request \(response.id) failed in \(String(format: "%.3f", duration))s - Error: \(response.error ?? "unknown")")
                }

                completion(response)
            }
        }
    }
    
    /// Process a request synchronously (must be called on realmQueue)
    private func processRequest(_ request: InspectorRequest) -> InspectorResponse {
        do {
            let data = try executeRequest(request)
            return .success(id: request.id, data: data)
        } catch {
            return .failure(id: request.id, error: error.localizedDescription)
        }
    }
    
    // MARK: - Request Execution
    
    private func executeRequest(_ request: InspectorRequest) throws -> AnyCodable? {
        switch request.type {
        case .ping:
            return AnyCodable(["pong": true, "timestamp": Date().timeIntervalSince1970])
            
        case .getRealmInfo:
            return try executeGetRealmInfo()
            
        case .listSchemas:
            return try executeListSchemas()
            
        case .getSchema:
            return try executeGetSchema(request.params)
            
        case .queryDocuments:
            return try executeQueryDocuments(request.params)
            
        case .getDocument:
            return try executeGetDocument(request.params)
            
        case .countDocuments:
            return try executeCountDocuments(request.params)
            
        case .createDocument:
            return try executeCreateDocument(request.params)
            
        case .updateDocument:
            return try executeUpdateDocument(request.params)
            
        case .deleteDocument:
            return try executeDeleteDocument(request.params)
            
        case .subscribe:
            return try executeSubscribe(request.params)
            
        case .unsubscribe:
            return try executeUnsubscribe(request.params)
        }
    }
    
    // MARK: - Request Implementations

    /// Extract the actual primary key value from structured representations
    /// Handles ObjectId format: ["_type": "ObjectId", "value": "..."]
    private func extractPrimaryKey(from value: Any) -> Any {
        // Check if this is a structured representation
        if let dict = value as? [String: Any],
           let type = dict["_type"] as? String,
           let keyValue = dict["value"] {

            // For ObjectId, return the string value
            if type == "ObjectId" {
                return keyValue
            }

            // For other types, return the value
            return keyValue
        }

        // Not a structured type, return as-is
        return value
    }

    private func executeGetRealmInfo() throws -> AnyCodable {
        Logger.log("ℹ️  Getting Realm info")
        let info = schemaExtractor.getRealmInfo()
        Logger.log("📊 Realm info - Path: \(info.path), Version: \(info.schemaVersion), Objects: \(info.objectCount), InMemory: \(info.isInMemory)")
        return AnyCodable([
            "path": info.path,
            "schemaVersion": info.schemaVersion,
            "objectCount": info.objectCount,
            "fileSize": info.fileSize as Any,
            "isInMemory": info.isInMemory,
            "isSyncEnabled": info.isSyncEnabled
        ])
    }
    
    private func executeListSchemas() throws -> AnyCodable {
        Logger.log("📋 Listing all schemas")
        let schemas = schemaExtractor.getAllSchemas()
        Logger.log("📊 Found \(schemas.count) schemas: \(schemas.map { $0.name }.joined(separator: ", "))")
        let schemaData = schemas.map { schema -> [String: Any] in
            [
                "name": schema.name,
                "primaryKey": schema.primaryKey as Any,
                "propertyCount": schema.properties.count,
                "isEmbedded": schema.isEmbedded,
                "objectCount": schemaExtractor.getObjectCount(forTypeName: schema.name)
            ]
        }
        return AnyCodable(schemaData)
    }
    
    private func executeGetSchema(_ params: [String: AnyCodable]?) throws -> AnyCodable {
        guard let typeName = params?["typeName"]?.value as? String else {
            Logger.log("❌ Missing typeName parameter for getSchema")
            throw RequestError.missingParameter("typeName")
        }

        Logger.log("📄 Getting schema for type: \(typeName)")

        guard let schema = schemaExtractor.getSchema(forTypeName: typeName) else {
            Logger.log("❌ Schema not found: \(typeName)")
            throw RequestError.notFound("Schema '\(typeName)' not found")
        }

        Logger.log("✅ Schema found - Type: \(typeName), Properties: \(schema.properties.count), PrimaryKey: \(schema.primaryKey ?? "none")")

        let propertyData = schema.properties.map { prop -> [String: Any] in
            [
                "name": prop.name,
                "type": prop.type,
                "isOptional": prop.isOptional,
                "isPrimaryKey": prop.isPrimaryKey,
                "isIndexed": prop.isIndexed,
                "objectClassName": prop.objectClassName as Any
            ]
        }

        return AnyCodable([
            "name": schema.name,
            "primaryKey": schema.primaryKey as Any,
            "properties": propertyData,
            "isEmbedded": schema.isEmbedded
        ])
    }
    
    private func executeQueryDocuments(_ params: [String: AnyCodable]?) throws -> AnyCodable {
        guard let queryParams = QueryParams.from(params: params) else {
            Logger.log("❌ Missing typeName parameter for queryDocuments")
            throw RequestError.missingParameter("typeName")
        }

        Logger.log("🔍 Querying documents - Type: \(queryParams.typeName), Skip: \(queryParams.skip), Limit: \(queryParams.limit)")
        if let filter = queryParams.filter {
            Logger.log("   Filter: \(filter)")
        }
        if let sortKeyPath = queryParams.sortKeyPath {
            Logger.log("   Sort: \(sortKeyPath) (\(queryParams.ascending ? "ascending" : "descending"))")
        }

        let result = try queryExecutor.execute(queryParams)

        Logger.log("📊 Query results - Found: \(result.documents.count), Total: \(result.totalCount), HasMore: \(result.hasMore)")

        return AnyCodable([
            "documents": result.documents.map { $0.mapValues { $0.value } },
            "totalCount": result.totalCount,
            "skip": result.skip,
            "limit": result.limit,
            "hasMore": result.hasMore
        ])
    }
    
    private func executeGetDocument(_ params: [String: AnyCodable]?) throws -> AnyCodable {
        guard let typeName = params?["typeName"]?.value as? String else {
            Logger.log("❌ Missing typeName parameter for getDocument")
            throw RequestError.missingParameter("typeName")
        }

        guard let primaryKeyValue = params?["primaryKey"]?.value else {
            Logger.log("❌ Missing primaryKey parameter for getDocument")
            throw RequestError.missingParameter("primaryKey")
        }

        // Extract the actual primary key value from structured representations
        let primaryKey = extractPrimaryKey(from: primaryKeyValue)

        Logger.log("📄 Getting document - Type: \(typeName), PrimaryKey: \(primaryKey)")

        guard let document = try queryExecutor.getDocument(typeName: typeName, primaryKey: primaryKey) else {
            Logger.log("❌ Document not found - Type: \(typeName), PrimaryKey: \(primaryKey)")
            throw RequestError.notFound("Document not found")
        }

        Logger.log("✅ Document retrieved - Type: \(typeName), Properties: \(document.keys.count)")

        return AnyCodable(document)
    }
    
    private func executeCountDocuments(_ params: [String: AnyCodable]?) throws -> AnyCodable {
        guard let typeName = params?["typeName"]?.value as? String else {
            Logger.log("❌ Missing typeName parameter for countDocuments")
            throw RequestError.missingParameter("typeName")
        }

        let filter = params?["filter"]?.value as? String
        Logger.log("🔢 Counting documents - Type: \(typeName)\(filter.map { ", Filter: \($0)" } ?? "")")

        let count = try queryExecutor.count(typeName: typeName, filter: filter)

        Logger.log("📊 Count result - Type: \(typeName), Count: \(count)")

        return AnyCodable(["count": count])
    }
    
    private func executeCreateDocument(_ params: [String: AnyCodable]?) throws -> AnyCodable {
        guard let typeName = params?["typeName"]?.value as? String else {
            Logger.log("❌ Missing typeName parameter for createDocument")
            throw RequestError.missingParameter("typeName")
        }

        guard let data = params?["data"]?.value as? [String: Any] else {
            Logger.log("❌ Missing data parameter for createDocument")
            throw RequestError.missingParameter("data")
        }

        Logger.log("➕ Creating document - Type: \(typeName), Fields: \(data.keys.joined(separator: ", "))")

        let document = try queryExecutor.createDocument(typeName: typeName, data: data)

        Logger.log("✅ Document created - Type: \(typeName)")

        return AnyCodable(document)
    }
    
    private func executeUpdateDocument(_ params: [String: AnyCodable]?) throws -> AnyCodable {
        guard let typeName = params?["typeName"]?.value as? String else {
            Logger.log("❌ Missing typeName parameter for updateDocument")
            throw RequestError.missingParameter("typeName")
        }

        guard let primaryKeyValue = params?["primaryKey"]?.value else {
            Logger.log("❌ Missing primaryKey parameter for updateDocument")
            throw RequestError.missingParameter("primaryKey")
        }

        guard let changes = params?["changes"]?.value as? [String: Any] else {
            Logger.log("❌ Missing changes parameter for updateDocument")
            throw RequestError.missingParameter("changes")
        }

        // Extract the actual primary key value from structured representations
        let primaryKey = extractPrimaryKey(from: primaryKeyValue)

        Logger.log("✏️  Updating document - Type: \(typeName), PrimaryKey: \(primaryKey), Changing fields: \(changes.keys.joined(separator: ", "))")

        let document = try queryExecutor.updateDocument(typeName: typeName, primaryKey: primaryKey, changes: changes)

        Logger.log("✅ Document updated - Type: \(typeName), PrimaryKey: \(primaryKey)")

        return AnyCodable(document)
    }
    
    private func executeDeleteDocument(_ params: [String: AnyCodable]?) throws -> AnyCodable {
        guard let typeName = params?["typeName"]?.value as? String else {
            Logger.log("❌ Missing typeName parameter for deleteDocument")
            throw RequestError.missingParameter("typeName")
        }

        guard let primaryKeyValue = params?["primaryKey"]?.value else {
            Logger.log("❌ Missing primaryKey parameter for deleteDocument")
            throw RequestError.missingParameter("primaryKey")
        }

        // Extract the actual primary key value from structured representations
        let primaryKey = extractPrimaryKey(from: primaryKeyValue)

        Logger.log("🗑️  Deleting document - Type: \(typeName), PrimaryKey: \(primaryKey)")

        let deleted = try queryExecutor.deleteDocument(typeName: typeName, primaryKey: primaryKey)

        if deleted {
            Logger.log("✅ Document deleted - Type: \(typeName), PrimaryKey: \(primaryKey)")
        } else {
            Logger.log("⚠️  Document not found for deletion - Type: \(typeName), PrimaryKey: \(primaryKey)")
        }

        return AnyCodable(["deleted": deleted])
    }
    
    private func executeSubscribe(_ params: [String: AnyCodable]?) throws -> AnyCodable {
        guard let typeName = params?["typeName"]?.value as? String else {
            Logger.log("❌ Missing typeName parameter for subscribe")
            throw RequestError.missingParameter("typeName")
        }

        // Generate subscription ID
        let subscriptionId = UUID().uuidString

        let filter = params?["filter"]?.value as? String
        Logger.log("🔔 Creating subscription - ID: \(subscriptionId), Type: \(typeName)\(filter.map { ", Filter: \($0)" } ?? "")")

        // The actual subscription setup will be handled by the InspectorServer
        // This just validates and returns the subscription ID

        return AnyCodable([
            "subscriptionId": subscriptionId,
            "typeName": typeName,
            "filter": params?["filter"]?.value as Any
        ])
    }
    
    private func executeUnsubscribe(_ params: [String: AnyCodable]?) throws -> AnyCodable {
        guard let subscriptionId = params?["subscriptionId"]?.value as? String else {
            Logger.log("❌ Missing subscriptionId parameter for unsubscribe")
            throw RequestError.missingParameter("subscriptionId")
        }

        Logger.log("🔕 Unsubscribing - ID: \(subscriptionId)")

        // The actual unsubscribe will be handled by the InspectorServer
        return AnyCodable(["unsubscribed": subscriptionId])
    }
}

// MARK: - Request Errors

public enum RequestError: Error, LocalizedError {
    case missingParameter(String)
    case invalidParameter(String, String)
    case notFound(String)
    case operationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .missingParameter(let param):
            return "Missing required parameter: \(param)"
        case .invalidParameter(let param, let reason):
            return "Invalid parameter '\(param)': \(reason)"
        case .notFound(let message):
            return message
        case .operationFailed(let message):
            return "Operation failed: \(message)"
        }
    }
}
