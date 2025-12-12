import Foundation

/// A type-erased Codable value that can represent any JSON-compatible type.
/// Used for dynamic serialization of Realm objects.
public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any?) {
        self.value = value ?? NSNull()
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let int64 = try? container.decode(Int64.self) {
            value = int64
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode AnyCodable"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let int64 as Int64:
            try container.encode(int64)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let date as Date:
            try container.encode(ISO8601DateFormatter().string(from: date))
        case let data as Data:
            try container.encode(data.base64EncodedString())
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            // Try to encode as string representation
            try container.encode(String(describing: value))
        }
    }
}

// MARK: - ExpressibleBy Literals

extension AnyCodable: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self.init(NSNull())
    }
}

extension AnyCodable: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self.init(value)
    }
}

extension AnyCodable: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self.init(value)
    }
}

extension AnyCodable: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self.init(value)
    }
}

extension AnyCodable: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

extension AnyCodable: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Any...) {
        self.init(elements)
    }
}

extension AnyCodable: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Any)...) {
        self.init(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - Equatable

extension AnyCodable: Equatable {
    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case is (NSNull, NSNull):
            return true
        case let (lhs as Bool, rhs as Bool):
            return lhs == rhs
        case let (lhs as Int, rhs as Int):
            return lhs == rhs
        case let (lhs as Int64, rhs as Int64):
            return lhs == rhs
        case let (lhs as Double, rhs as Double):
            return lhs == rhs
        case let (lhs as String, rhs as String):
            return lhs == rhs
        case let (lhs as [Any], rhs as [Any]):
            return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { AnyCodable($0) == AnyCodable($1) }
        case let (lhs as [String: Any], rhs as [String: Any]):
            return lhs.count == rhs.count && lhs.allSatisfy { key, value in
                rhs[key].map { AnyCodable(value) == AnyCodable($0) } ?? false
            }
        default:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension AnyCodable: CustomStringConvertible {
    public var description: String {
        switch value {
        case is NSNull:
            return "null"
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as any Numeric:
            return "\(number)"
        case let string as String:
            return "\"\(string)\""
        case let array as [Any]:
            let items = array.map { AnyCodable($0).description }.joined(separator: ", ")
            return "[\(items)]"
        case let dict as [String: Any]:
            let pairs = dict.map { "\"\($0)\": \(AnyCodable($1).description)" }.joined(separator: ", ")
            return "{\(pairs)}"
        default:
            return String(describing: value)
        }
    }
}

// MARK: - Convenience Accessors

extension AnyCodable {
    /// Access value as a specific type
    public func value<T>(as type: T.Type) -> T? {
        return value as? T
    }
    
    /// Access nested dictionary value by key
    public subscript(key: String) -> AnyCodable? {
        guard let dict = value as? [String: Any] else { return nil }
        return dict[key].map { AnyCodable($0) }
    }
    
    /// Access array element by index
    public subscript(index: Int) -> AnyCodable? {
        guard let array = value as? [Any], index >= 0, index < array.count else { return nil }
        return AnyCodable(array[index])
    }
    
    /// Check if the value is null
    public var isNull: Bool {
        return value is NSNull
    }
    
    /// Convert to dictionary if possible
    public var dictionary: [String: Any]? {
        return value as? [String: Any]
    }
    
    /// Convert to array if possible
    public var array: [Any]? {
        return value as? [Any]
    }
}
