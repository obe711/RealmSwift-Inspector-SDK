import Foundation
import RealmSwift

/// Converts Realm objects to dictionary representations suitable for JSON serialization.
/// Handles all Realm property types including links, lists, and embedded objects.
public final class ObjectSerializer {
    
    // MARK: - Configuration
    
    /// Controls how deeply nested objects are serialized
    public var maxDepth: Int = 3
    
    /// Controls whether to include linking objects
    public var includeLinkingObjects: Bool = false
    
    /// Maximum number of items to include in lists (for performance)
    public var maxListItems: Int = 100
    
    /// Whether to include metadata like _id formatting
    public var includeMetadata: Bool = true
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Serialization
    
    /// Serialize a DynamicObject to a dictionary
    public func serialize(_ object: DynamicObject, depth: Int = 0) -> [String: Any] {
        guard depth < maxDepth else {
            return ["_truncated": true, "_reason": "Max depth exceeded"]
        }
        
        var result: [String: Any] = [:]
        
        let objectSchema = object.objectSchema
        
        for property in objectSchema.properties {
            let value = serializeProperty(property, from: object, depth: depth)
            result[property.name] = value
        }
        
        // Add _type metadata if enabled
        if includeMetadata {
            result["_type"] = objectSchema.className
        }
        
        return result
    }
    
    /// Serialize an array of DynamicObjects
    public func serialize(_ objects: [DynamicObject]) -> [[String: Any]] {
        return objects.map { serialize($0) }
    }
    
    /// Serialize Results to an array of dictionaries
    public func serialize(_ results: Results<DynamicObject>) -> [[String: Any]] {
        return Array(results.prefix(maxListItems)).map { serialize($0) }
    }
    
    // MARK: - Property Serialization
    
    private func serializeProperty(_ property: Property, from object: DynamicObject, depth: Int) -> Any {
        // Handle optional nil values
        if property.isOptional {
            if isNil(property: property, in: object) {
                return NSNull()
            }
        }
        
        switch property.type {
        case .int:
            return object[property.name] as? Int ?? 0
            
        case .bool:
            return object[property.name] as? Bool ?? false
            
        case .float:
            return object[property.name] as? Float ?? 0.0
            
        case .double:
            return object[property.name] as? Double ?? 0.0
            
        case .string:
            return object[property.name] as? String ?? ""
            
        case .data:
            if let data = object[property.name] as? Data {
                return serializeData(data)
            }
            return NSNull()
            
        case .date:
            if let date = object[property.name] as? Date {
                return serializeDate(date)
            }
            return NSNull()
            
        case .objectId:
            if let objectId = object[property.name] as? ObjectId {
                return serializeObjectId(objectId)
            }
            return NSNull()
            
        case .decimal128:
            if let decimal = object[property.name] as? Decimal128 {
                return decimal.stringValue
            }
            return NSNull()
            
//        case .uuid:
//            if let uuid = object[property.name] as? UUID {
//                return uuid.uuidString
//            }
//            return NSNull()
            
        case .object:
            return serializeLinkedObject(property, from: object, depth: depth)
            
        case .any:
            if let anyValue = object[property.name] as? AnyRealmValue {
                return serializeAnyRealmValue(anyValue, depth: depth)
            }
            return NSNull()
            
        case .linkingObjects:
            if includeLinkingObjects {
                return serializeLinkingObjects(property, from: object, depth: depth)
            }
            return ["_type": "LinkingObjects", "_excluded": true]
            
        @unknown default:
            return ["_error": "Unknown property type"]
        }
    }
    
    // MARK: - Type-Specific Serialization
    
    private func serializeData(_ data: Data) -> [String: Any] {
        return [
            "_type": "Data",
            "length": data.count,
            "preview": data.prefix(64).base64EncodedString(),
            "truncated": data.count > 64
        ]
    }
    
    private func serializeDate(_ date: Date) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return [
            "_type": "Date",
            "iso": formatter.string(from: date),
            "timestamp": date.timeIntervalSince1970
        ]
    }
    
    private func serializeObjectId(_ objectId: ObjectId) -> [String: Any] {
        return [
            "_type": "ObjectId",
            "value": objectId.stringValue
        ]
    }
    
    private func serializeLinkedObject(_ property: Property, from object: DynamicObject, depth: Int) -> Any {
        guard let linkedObject = object[property.name] as? DynamicObject else {
            return NSNull()
        }
        
        if depth + 1 >= maxDepth {
            // Return a reference instead of full object
            return createReference(to: linkedObject, typeName: property.objectClassName)
        }
        
        return serialize(linkedObject, depth: depth + 1)
    }
    
    private func serializeLinkingObjects(_ property: Property, from object: DynamicObject, depth: Int) -> Any {
        // LinkingObjects require special handling through the schema
        guard let linkingObjects = object.dynamicList(property.name) as? Results<DynamicObject> else {
            return []
        }
        
        let count = linkingObjects.count
        let items = Array(linkingObjects.prefix(maxListItems)).map { linkedObject -> Any in
            if depth + 1 >= maxDepth {
                return createReference(to: linkedObject, typeName: property.objectClassName)
            }
            return serialize(linkedObject, depth: depth + 1)
        }
        
        return [
            "_type": "LinkingObjects",
            "_count": count,
            "_items": items,
            "_truncated": count > maxListItems
        ]
    }
    
    private func serializeAnyRealmValue(_ value: AnyRealmValue, depth: Int) -> Any {
        switch value {
        case .none:
            return NSNull()
        case .int(let int):
            return int
        case .bool(let bool):
            return bool
        case .float(let float):
            return float
        case .double(let double):
            return double
        case .string(let string):
            return string
        case .data(let data):
            return serializeData(data)
        case .date(let date):
            return serializeDate(date)
        case .objectId(let objectId):
            return serializeObjectId(objectId)
        case .decimal128(let decimal):
            return ["_type": "Decimal128", "value": decimal.stringValue]
        case .uuid(let uuid):
            return uuid.uuidString
        case .object(let object):
            if let dynamicObject = object as? DynamicObject {
                if depth + 1 >= maxDepth {
                    return createReference(to: dynamicObject, typeName: nil)
                }
                return serialize(dynamicObject, depth: depth + 1)
            }
            return ["_error": "Unknown object type"]
        @unknown default:
            return ["_error": "Unknown AnyRealmValue type"]
        }
    }
    
    // MARK: - Helpers
    
    private func isNil(property: Property, in object: DynamicObject) -> Bool {
        // Access the underlying value and check for nil
        let value = object[property.name]
        return value == nil || value is NSNull
    }
    
    private func createReference(to object: DynamicObject, typeName: String?) -> [String: Any] {
        var ref: [String: Any] = [
            "_type": "Reference",
            "_typeName": typeName ?? object.objectSchema.className
        ]
        
        // Try to include primary key if available
        if let pkProperty = object.objectSchema.primaryKeyProperty {
            let pkValue = object[pkProperty.name]
            if let objectId = pkValue as? ObjectId {
                ref["_id"] = objectId.stringValue
            } else if let stringKey = pkValue as? String {
                ref["_id"] = stringKey
            } else if let intKey = pkValue as? Int {
                ref["_id"] = intKey
            }
        }
        
        return ref
    }
}

// MARK: - List Serialization Extension

extension ObjectSerializer {
    
    /// Serialize a Realm List property
    public func serializeList<T>(_ list: List<T>) -> [Any] where T: RealmCollectionValue {
        return Array(list.prefix(maxListItems)).compactMap { item -> Any? in
            if let dynamicObject = item as? DynamicObject {
                return serialize(dynamicObject)
            }
            return item
        }
    }
    
    /// Serialize a Map property
    public func serializeMap<K, V>(_ map: Map<K, V>) -> [String: Any] where K: _MapKey, V: RealmCollectionValue {
        var result: [String: Any] = [:]
        
        for key in map.keys.prefix(maxListItems) {
            let keyString = String(describing: key)
            if let value = map[key] {
                if let dynamicObject = value as? DynamicObject {
                    result[keyString] = serialize(dynamicObject)
                } else {
                    result[keyString] = value
                }
            }
        }
        
        return result
    }
}

// MARK: - Formatted Output

extension ObjectSerializer {
    
    /// Serialize to pretty-printed JSON string
    public func serializeToJSON(_ object: DynamicObject, prettyPrint: Bool = true) throws -> String {
        let dict = serialize(object)
        let options: JSONSerialization.WritingOptions = prettyPrint ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try JSONSerialization.data(withJSONObject: dict, options: options)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    /// Serialize results to JSON array string
    public func serializeToJSON(_ results: Results<DynamicObject>, prettyPrint: Bool = true) throws -> String {
        let array = serialize(results)
        let options: JSONSerialization.WritingOptions = prettyPrint ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try JSONSerialization.data(withJSONObject: array, options: options)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
