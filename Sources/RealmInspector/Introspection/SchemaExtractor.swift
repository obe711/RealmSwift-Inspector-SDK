import Foundation
import RealmSwift

/// Extracts schema information from a Realm instance
public final class SchemaExtractor {
    
    private let realm: Realm
    
    public init(realm: Realm) {
        self.realm = realm
    }
    
    // MARK: - Schema Extraction
    
    /// Get all object schemas in the Realm
    public func getAllSchemas() -> [SchemaInfo] {
        return realm.schema.objectSchema.map { extractSchema(from: $0) }
    }
    
    /// Get schema for a specific type name
    public func getSchema(forTypeName typeName: String) -> SchemaInfo? {
        guard let objectSchema = realm.schema.objectSchema.first(where: { $0.className == typeName }) else {
            return nil
        }
        return extractSchema(from: objectSchema)
    }
    
    /// Get all type names in the Realm
    public func getAllTypeNames() -> [String] {
        return realm.schema.objectSchema.map { $0.className }
    }
    
    /// Check if a type exists in the schema
    public func hasType(_ typeName: String) -> Bool {
        return realm.schema.objectSchema.contains { $0.className == typeName }
    }
    
    // MARK: - Private Helpers
    
    private func extractSchema(from objectSchema: ObjectSchema) -> SchemaInfo {
        let properties = objectSchema.properties.map { extractProperty(from: $0, primaryKey: objectSchema.primaryKeyProperty?.name) }
        
        return SchemaInfo(
            name: objectSchema.className,
            primaryKey: objectSchema.primaryKeyProperty?.name,
            properties: properties,
            isEmbedded: objectSchema.isEmbedded
        )
    }
    
    private func extractProperty(from property: Property, primaryKey: String?) -> PropertyInfo {
        return PropertyInfo(
            name: property.name,
            type: propertyTypeString(property),
            isOptional: property.isOptional,
            isPrimaryKey: property.name == primaryKey,
            isIndexed: property.isIndexed,
            objectClassName: property.objectClassName
        )
    }
    
    private func propertyTypeString(_ property: Property) -> String {
        switch property.type {
        case .int:
            return "Int"
        case .bool:
            return "Bool"
        case .float:
            return "Float"
        case .double:
            return "Double"
        case .string:
            return "String"
        case .data:
            return "Data"
        case .date:
            return "Date"
        case .object:
            if let objectClassName = property.objectClassName {
                return "Link<\(objectClassName)>"
            }
            return "Object"
        case .objectId:
            return "ObjectId"
        case .decimal128:
            return "Decimal128"
//        case .uuid:
//            return "UUID"
        case .any:
            return "AnyRealmValue"
        case .linkingObjects:
            if let objectClassName = property.objectClassName {
                return "LinkingObjects<\(objectClassName)>"
            }
            return "LinkingObjects"
        @unknown default:
            return "Unknown"
        }
    }
}

// MARK: - Realm Info

extension SchemaExtractor {
    
    /// Get comprehensive information about the Realm instance
    public func getRealmInfo() -> RealmInfo {
        let config = realm.configuration
        let path = config.fileURL?.path ?? "in-memory"
        
        // Calculate total object count
        let objectCount = realm.schema.objectSchema.reduce(0) { count, schema in
            count + realm.dynamicObjects(schema.className).count
        }
        
        // Get file size if available
        var fileSize: Int64? = nil
        if let fileURL = config.fileURL {
            fileSize = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64
        }
        
        return RealmInfo(
            path: path,
            schemaVersion: config.schemaVersion,
            objectCount: objectCount,
            fileSize: fileSize,
            isInMemory: config.inMemoryIdentifier != nil,
            isSyncEnabled: config.syncConfiguration != nil
        )
    }
    
    /// Get object count for a specific type
    public func getObjectCount(forTypeName typeName: String) -> Int {
        return realm.dynamicObjects(typeName).count
    }
}

// MARK: - Type Resolution

extension SchemaExtractor {
    
    /// Get the primary key property name for a type
    public func getPrimaryKey(forTypeName typeName: String) -> String? {
        return realm.schema.objectSchema.first { $0.className == typeName }?.primaryKeyProperty?.name
    }
    
    /// Check if a type has a specific property
    public func hasProperty(_ propertyName: String, forTypeName typeName: String) -> Bool {
        guard let objectSchema = realm.schema.objectSchema.first(where: { $0.className == typeName }) else {
            return false
        }
        return objectSchema.properties.contains { $0.name == propertyName }
    }
    
    /// Get property info for a specific property
    public func getPropertyInfo(propertyName: String, forTypeName typeName: String) -> PropertyInfo? {
        guard let objectSchema = realm.schema.objectSchema.first(where: { $0.className == typeName }),
              let property = objectSchema.properties.first(where: { $0.name == propertyName }) else {
            return nil
        }
        return extractProperty(from: property, primaryKey: objectSchema.primaryKeyProperty?.name)
    }
}
