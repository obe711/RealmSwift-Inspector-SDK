import Foundation
import SwiftUI

/// Represents a type of value in a document
public enum DocumentValueType {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case objectId(String)
    case date(iso: String, timestamp: Double)
    case data(length: Int, preview: String)
    case object([String: Any])
    case array([Any])
    case reference(typeName: String, id: String?)
    case unknown(String)
    
    /// Display name for the type
    public var typeName: String {
        switch self {
        case .null: return "null"
        case .bool: return "Bool"
        case .int: return "Int"
        case .double: return "Double"
        case .string: return "String"
        case .objectId: return "ObjectId"
        case .date: return "Date"
        case .data: return "Data"
        case .object: return "Object"
        case .array: return "Array"
        case .reference(let typeName, _): return "Link<\(typeName)>"
        case .unknown: return "Unknown"
        }
    }
    
    /// Color for syntax highlighting
    public var color: Color {
        switch self {
        case .null: return .gray
        case .bool: return .purple
        case .int, .double: return .blue
        case .string: return .green
        case .objectId: return .yellow
        case .date: return .orange
        case .data: return .pink
        case .object: return .white
        case .array: return .white
        case .reference: return .blue
        case .unknown: return .gray
        }
    }
    
    /// Whether this type can be expanded
    public var isExpandable: Bool {
        switch self {
        case .object, .array, .reference:
            return true
        default:
            return false
        }
    }
    
    /// Child count for expandable types
    public var childCount: Int {
        switch self {
        case .object(let dict):
            return dict.count
        case .array(let arr):
            return arr.count
        default:
            return 0
        }
    }
}

/// A node in the document tree
public struct DocumentNode: Identifiable {
    public let id: String
    public let key: String
    public let value: DocumentValueType
    public let depth: Int
    public var isExpanded: Bool = false
    
    public init(key: String, value: Any?, depth: Int = 0, parentId: String = "") {
        self.id = parentId.isEmpty ? key : "\(parentId).\(key)"
        self.key = key
        self.depth = depth
        self.value = Self.parseValue(value)
    }
    
    /// Parse a raw value into a DocumentValueType
    private static func parseValue(_ value: Any?) -> DocumentValueType {
        guard let value = value else {
            return .null
        }

        // Check for NSNull
        if value is NSNull {
            return .null
        }
        
        // Check for special object types first
        if let dict = value as? [String: Any] {
            // Check for ObjectId
            if let type = dict["_type"] as? String {
                switch type {
                case "ObjectId":
                    return .objectId(dict["value"] as? String ?? "")
                    
                case "Date":
                    return .date(
                        iso: dict["iso"] as? String ?? "",
                        timestamp: dict["timestamp"] as? Double ?? 0
                    )
                    
                case "Data":
                    return .data(
                        length: dict["length"] as? Int ?? 0,
                        preview: dict["preview"] as? String ?? ""
                    )
                    
                case "Reference":
                    return .reference(
                        typeName: dict["_typeName"] as? String ?? "Unknown",
                        id: dict["_id"] as? String
                    )
                    
                default:
                    break
                }
            }
            
            return .object(dict)
        }
        
        if let array = value as? [Any] {
            return .array(array)
        }
        
        if let bool = value as? Bool {
            return .bool(bool)
        }
        
        if let int = value as? Int {
            return .int(int)
        }
        
        if let double = value as? Double {
            return .double(double)
        }
        
        if let string = value as? String {
            return .string(string)
        }
        
        return .unknown(String(describing: value))
    }
    
    /// Generate child nodes for expandable types
    public func childNodes() -> [DocumentNode] {
        switch value {
        case .object(let dict):
            return dict.sorted { $0.key < $1.key }.map { key, value in
                DocumentNode(key: key, value: value, depth: depth + 1, parentId: id)
            }
            
        case .array(let array):
            return array.enumerated().map { index, value in
                DocumentNode(key: "[\(index)]", value: value, depth: depth + 1, parentId: id)
            }
            
        default:
            return []
        }
    }
    
    /// Format the value for display
    public var displayValue: String {
        switch value {
        case .null:
            return "null"
        case .bool(let bool):
            return bool ? "true" : "false"
        case .int(let int):
            return String(int)
        case .double(let double):
            return String(format: "%.6g", double)
        case .string(let string):
            return "\"\(string)\""
        case .objectId(let id):
            return "ObjectId('\(id)')"
        case .date(let iso, _):
            return iso
        case .data(let length, _):
            return "Binary(\(length) bytes)"
        case .object(let dict):
            return "{ \(dict.count) fields }"
        case .array(let array):
            return "[ \(array.count) items ]"
        case .reference(let typeName, let id):
            if let id = id {
                return "→ \(typeName)(\(id))"
            }
            return "→ \(typeName)"
        case .unknown(let desc):
            return desc
        }
    }
}

/// Extension to create nodes from a document
extension DocumentNode {
    
    /// Create root nodes from a document dictionary
    public static func fromDocument(_ document: [String: Any]) -> [DocumentNode] {
        // Sort keys, but put _id first if present
        var sortedKeys = document.keys.sorted()
        if let idIndex = sortedKeys.firstIndex(of: "_id") {
            sortedKeys.remove(at: idIndex)
            sortedKeys.insert("_id", at: 0)
        }
        
        return sortedKeys.map { key in
            DocumentNode(key: key, value: document[key], depth: 0)
        }
    }
}
