import Foundation

// MARK: - Request Types

/// All possible request types from the desktop client
public enum RequestType: String, Codable, CaseIterable {
    // Schema operations
    case listSchemas
    case getSchema
    
    // Document operations
    case queryDocuments
    case getDocument
    case countDocuments
    
    // Mutation operations
    case createDocument
    case updateDocument
    case deleteDocument
    case deleteAllInCollection
    case deleteAllInDatabase

    // Subscription operations
    case subscribe
    case unsubscribe
    
    // Connection operations
    case ping
    case getRealmInfo
}

// MARK: - Request

/// A request from the desktop client to the iOS SDK
public struct InspectorRequest: Codable, Identifiable {
    public let id: String
    public let type: RequestType
    public let params: [String: AnyCodable]?
    
    public init(id: String = UUID().uuidString, type: RequestType, params: [String: AnyCodable]? = nil) {
        self.id = id
        self.type = type
        self.params = params
    }
}

// MARK: - Response

/// A response from the iOS SDK to the desktop client
public struct InspectorResponse: Codable {
    public let id: String
    public let success: Bool
    public let data: AnyCodable?
    public let error: String?
    public let timestamp: Date
    
    public init(id: String, success: Bool, data: AnyCodable? = nil, error: String? = nil) {
        self.id = id
        self.success = success
        self.data = data
        self.error = error
        self.timestamp = Date()
    }
    
    public static func success(id: String, data: AnyCodable?) -> InspectorResponse {
        InspectorResponse(id: id, success: true, data: data)
    }
    
    public static func failure(id: String, error: String) -> InspectorResponse {
        InspectorResponse(id: id, success: false, error: error)
    }
}

// MARK: - Change Notification

/// Real-time change notification pushed to subscribed clients
public struct ChangeNotification: Codable {
    public let subscriptionId: String
    public let typeName: String
    public let changes: ChangeSet
    public let timestamp: Date
    
    public init(subscriptionId: String, typeName: String, changes: ChangeSet) {
        self.subscriptionId = subscriptionId
        self.typeName = typeName
        self.changes = changes
        self.timestamp = Date()
    }
}

/// Describes changes to a Realm collection
public struct ChangeSet: Codable {
    public let insertions: [AnyCodable]
    public let modifications: [AnyCodable]
    public let deletions: [String]  // Primary keys of deleted objects
    
    public init(insertions: [AnyCodable] = [], modifications: [AnyCodable] = [], deletions: [String] = []) {
        self.insertions = insertions
        self.modifications = modifications
        self.deletions = deletions
    }
    
    public var isEmpty: Bool {
        insertions.isEmpty && modifications.isEmpty && deletions.isEmpty
    }
}

// MARK: - Schema Types

/// Represents a Realm object schema
public struct SchemaInfo: Codable {
    public let name: String
    public let primaryKey: String?
    public let properties: [PropertyInfo]
    public let isEmbedded: Bool
    
    public init(name: String, primaryKey: String?, properties: [PropertyInfo], isEmbedded: Bool = false) {
        self.name = name
        self.primaryKey = primaryKey
        self.properties = properties
        self.isEmbedded = isEmbedded
    }
}

/// Represents a property within a Realm schema
public struct PropertyInfo: Codable {
    public let name: String
    public let type: String
    public let isOptional: Bool
    public let isPrimaryKey: Bool
    public let isIndexed: Bool
    public let objectClassName: String?  // For links/lists
    
    public init(
        name: String,
        type: String,
        isOptional: Bool = false,
        isPrimaryKey: Bool = false,
        isIndexed: Bool = false,
        objectClassName: String? = nil
    ) {
        self.name = name
        self.type = type
        self.isOptional = isOptional
        self.isPrimaryKey = isPrimaryKey
        self.isIndexed = isIndexed
        self.objectClassName = objectClassName
    }
}

// MARK: - Realm Info

/// Information about the connected Realm instance
public struct RealmInfo: Codable {
    public let path: String
    public let schemaVersion: UInt64
    public let objectCount: Int
    public let fileSize: Int64?
    public let isInMemory: Bool
    public let isSyncEnabled: Bool
    
    public init(
        path: String,
        schemaVersion: UInt64,
        objectCount: Int,
        fileSize: Int64?,
        isInMemory: Bool,
        isSyncEnabled: Bool
    ) {
        self.path = path
        self.schemaVersion = schemaVersion
        self.objectCount = objectCount
        self.fileSize = fileSize
        self.isInMemory = isInMemory
        self.isSyncEnabled = isSyncEnabled
    }
}

// MARK: - Query Parameters

/// Parameters for querying documents
public struct QueryParams {
    public let typeName: String
    public let filter: String?
    public let sortKeyPath: String?
    public let ascending: Bool
    public let limit: Int
    public let skip: Int
    
    public init(
        typeName: String,
        filter: String? = nil,
        sortKeyPath: String? = nil,
        ascending: Bool = true,
        limit: Int = 50,
        skip: Int = 0
    ) {
        self.typeName = typeName
        self.filter = filter
        self.sortKeyPath = sortKeyPath
        self.ascending = ascending
        self.limit = limit
        self.skip = skip
    }
    
    public static func from(params: [String: AnyCodable]?) -> QueryParams? {
        guard let params = params,
              let typeName = params["typeName"]?.value as? String else {
            return nil
        }
        
        return QueryParams(
            typeName: typeName,
            filter: params["filter"]?.value as? String,
            sortKeyPath: params["sortKeyPath"]?.value as? String,
            ascending: params["ascending"]?.value as? Bool ?? true,
            limit: params["limit"]?.value as? Int ?? 50,
            skip: params["skip"]?.value as? Int ?? 0
        )
    }
}

// MARK: - Message Wrapper

/// Wrapper for all messages sent over the wire
public enum InspectorMessage: Codable {
    case request(InspectorRequest)
    case response(InspectorResponse)
    case notification(ChangeNotification)
    
    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }
    
    private enum MessageType: String, Codable {
        case request
        case response
        case notification
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)
        
        switch type {
        case .request:
            let payload = try container.decode(InspectorRequest.self, forKey: .payload)
            self = .request(payload)
        case .response:
            let payload = try container.decode(InspectorResponse.self, forKey: .payload)
            self = .response(payload)
        case .notification:
            let payload = try container.decode(ChangeNotification.self, forKey: .payload)
            self = .notification(payload)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .request(let request):
            try container.encode(MessageType.request, forKey: .type)
            try container.encode(request, forKey: .payload)
        case .response(let response):
            try container.encode(MessageType.response, forKey: .type)
            try container.encode(response, forKey: .payload)
        case .notification(let notification):
            try container.encode(MessageType.notification, forKey: .type)
            try container.encode(notification, forKey: .payload)
        }
    }
}
