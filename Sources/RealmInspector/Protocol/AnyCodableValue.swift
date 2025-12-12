//
//  AnyCodableValue.swift
//  RealmInspector
//
//  A type-erased Codable value for representing arbitrary JSON-like data
//

import Foundation

/// A type-erased wrapper that can hold any Codable value
/// Used for representing Realm objects in a serializable format
public enum AnyCodableValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case date(Date)
    case data(Data)
    case objectId(String)
    case uuid(String)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])
    
    // MARK: - Codable
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
            return
        }
        
        // Try decoding in order of specificity
        if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
            return
        }
        
        if let intValue = try? container.decode(Int64.self) {
            self = .int(intValue)
            return
        }
        
        if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
            return
        }
        
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }
        
        if let arrayValue = try? container.decode([AnyCodableValue].self) {
            self = .array(arrayValue)
            return
        }
        
        if let objectValue = try? container.decode([String: AnyCodableValue].self) {
            self = .object(objectValue)
            return
        }
        
        throw DecodingError.typeMismatch(
            AnyCodableValue.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode AnyCodableValue")
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .date(let value):
            // Encode dates as ISO8601 strings with a type hint
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let wrapper = TypedValue(type: "date", value: formatter.string(from: value))
            try container.encode(wrapper)
        case .data(let value):
            // Encode data as base64 with a type hint
            let wrapper = TypedValue(type: "data", value: value.base64EncodedString())
            try container.encode(wrapper)
        case .objectId(let value):
            let wrapper = TypedValue(type: "objectId", value: value)
            try container.encode(wrapper)
        case .uuid(let value):
            let wrapper = TypedValue(type: "uuid", value: value)
            try container.encode(wrapper)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

/// Helper for encoding typed values (dates, data, objectId)
private struct TypedValue: Codable {
    let type: String
    let value: String
    
    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case value = "$value"
    }
}

// MARK: - Convenience Initializers

public extension AnyCodableValue {
    
    init(_ value: Any?) {
        guard let value = value else {
            self = .null
            return
        }
        
        switch value {
        case let bool as Bool:
            self = .bool(bool)
        case let int as Int:
            self = .int(Int64(int))
        case let int64 as Int64:
            self = .int(int64)
        case let double as Double:
            self = .double(double)
        case let float as Float:
            self = .double(Double(float))
        case let string as String:
            self = .string(string)
        case let date as Date:
            self = .date(date)
        case let data as Data:
            self = .data(data)
        case let uuid as UUID:
            self = .uuid(uuid.uuidString)
        case let array as [Any]:
            self = .array(array.map { AnyCodableValue($0) })
        case let dict as [String: Any]:
            self = .object(dict.mapValues { AnyCodableValue($0) })
        default:
            self = .string(String(describing: value))
        }
    }
    
    /// Create from a dictionary
    static func from(_ dictionary: [String: Any]) -> AnyCodableValue {
        return .object(dictionary.mapValues { AnyCodableValue($0) })
    }
}

// MARK: - Value Extraction

public extension AnyCodableValue {
    
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
    
    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
    
    var intValue: Int64? {
        if case .int(let value) = self { return value }
        return nil
    }
    
    var doubleValue: Double? {
        if case .double(let value) = self { return value }
        if case .int(let value) = self { return Double(value) }
        return nil
    }
    
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
    
    var dateValue: Date? {
        if case .date(let value) = self { return value }
        return nil
    }
    
    var dataValue: Data? {
        if case .data(let value) = self { return value }
        return nil
    }
    
    var arrayValue: [AnyCodableValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
    
    var objectValue: [String: AnyCodableValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
    
    /// Subscript for object values
    subscript(key: String) -> AnyCodableValue? {
        if case .object(let dict) = self {
            return dict[key]
        }
        return nil
    }
    
    /// Subscript for array values
    subscript(index: Int) -> AnyCodableValue? {
        if case .array(let arr) = self, index >= 0 && index < arr.count {
            return arr[index]
        }
        return nil
    }
}

// MARK: - ExpressibleBy Protocols

extension AnyCodableValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension AnyCodableValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension AnyCodableValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(Int64(value))
    }
}

extension AnyCodableValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension AnyCodableValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension AnyCodableValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: AnyCodableValue...) {
        self = .array(elements)
    }
}

extension AnyCodableValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, AnyCodableValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - CustomStringConvertible

extension AnyCodableValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .string(let value):
            return "\"\(value)\""
        case .date(let value):
            let formatter = ISO8601DateFormatter()
            return "Date(\(formatter.string(from: value)))"
        case .data(let value):
            return "Data(\(value.count) bytes)"
        case .objectId(let value):
            return "ObjectId(\(value))"
        case .uuid(let value):
            return "UUID(\(value))"
        case .array(let value):
            return "[\(value.map { $0.description }.joined(separator: ", "))]"
        case .object(let value):
            let pairs = value.map { "\"\($0.key)\": \($0.value.description)" }
            return "{\(pairs.joined(separator: ", "))}"
        }
    }
}
