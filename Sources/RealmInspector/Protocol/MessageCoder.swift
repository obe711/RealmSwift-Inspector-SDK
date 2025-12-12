import Foundation

/// Handles encoding and decoding of messages with length-prefixed framing.
/// Each message is prefixed with a 4-byte big-endian length header.
public final class MessageCoder {
    
    // MARK: - Constants
    
    /// Size of the length prefix in bytes
    private static let headerSize = 4
    
    // MARK: - Encoder
    
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    public init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Encoding
    
    /// Encode a message with length prefix for wire transmission
    public func encode(_ message: InspectorMessage) throws -> Data {
        let payload = try encoder.encode(message)
        return packWithHeader(payload)
    }
    
    /// Encode a response with length prefix
    public func encode(_ response: InspectorResponse) throws -> Data {
        let message = InspectorMessage.response(response)
        return try encode(message)
    }
    
    /// Encode a notification with length prefix
    public func encode(_ notification: ChangeNotification) throws -> Data {
        let message = InspectorMessage.notification(notification)
        return try encode(message)
    }
    
    /// Encode any Codable value to JSON data (without length prefix)
    public func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        return try encoder.encode(value)
    }
    
    /// Pack data with a 4-byte big-endian length header
    private func packWithHeader(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        var result = Data(bytes: &length, count: Self.headerSize)
        result.append(payload)
        return result
    }
    
    // MARK: - Decoding
    
    /// Decode a message from length-prefixed data
    public func decode(_ data: Data) throws -> InspectorMessage {
        guard data.count >= Self.headerSize else {
            throw MessageCoderError.insufficientData
        }
        
        let payload = data.dropFirst(Self.headerSize)
        return try decoder.decode(InspectorMessage.self, from: Data(payload))
    }
    
    /// Decode a request from JSON data (without length prefix)
    public func decodeRequest(_ data: Data) throws -> InspectorRequest {
        return try decoder.decode(InspectorRequest.self, from: data)
    }
    
    /// Decode any Decodable value from JSON data
    public func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        return try decoder.decode(type, from: data)
    }
    
    // MARK: - Stream Decoding
    
    /// A stateful buffer for accumulating and extracting complete messages from a stream
    public class StreamBuffer {
        private var buffer = Data()
        private let coder: MessageCoder
        
        public init(coder: MessageCoder) {
            self.coder = coder
        }
        
        /// Append incoming data to the buffer
        public func append(_ data: Data) {
            buffer.append(data)
        }
        
        /// Extract all complete messages from the buffer
        public func extractMessages() throws -> [InspectorMessage] {
            var messages: [InspectorMessage] = []
            
            while let message = try extractNextMessage() {
                messages.append(message)
            }
            
            return messages
        }
        
        /// Extract the next complete message, or nil if not enough data
        private func extractNextMessage() throws -> InspectorMessage? {
            guard buffer.count >= MessageCoder.headerSize else {
                return nil
            }
            
            // Read length header
            let lengthData = buffer.prefix(MessageCoder.headerSize)
            let length = lengthData.withUnsafeBytes { ptr in
                ptr.loadUnaligned(as: UInt32.self).bigEndian
            }
            
            let totalLength = MessageCoder.headerSize + Int(length)
            
            guard buffer.count >= totalLength else {
                return nil // Not enough data yet
            }
            
            // Extract the complete message
            let messageData = buffer.prefix(totalLength)
            buffer = buffer.dropFirst(totalLength)
            
            return try coder.decode(Data(messageData))
        }
        
        /// Clear the buffer
        public func clear() {
            buffer.removeAll()
        }
        
        /// Current buffer size
        public var count: Int {
            buffer.count
        }
    }
    
    /// Create a new stream buffer
    public func createStreamBuffer() -> StreamBuffer {
        return StreamBuffer(coder: self)
    }
}

// MARK: - Errors

public enum MessageCoderError: Error, LocalizedError {
    case insufficientData
    case invalidHeader
    case encodingFailed(Error)
    case decodingFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .insufficientData:
            return "Insufficient data to decode message"
        case .invalidHeader:
            return "Invalid message header"
        case .encodingFailed(let error):
            return "Encoding failed: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Decoding failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Convenience Extensions

extension InspectorRequest {
    /// Create a simple request without parameters
    public static func simple(_ type: RequestType) -> InspectorRequest {
        InspectorRequest(type: type)
    }
    
    /// Create a request with parameters
    public static func with(_ type: RequestType, params: [String: Any]) -> InspectorRequest {
        InspectorRequest(type: type, params: params.mapValues { AnyCodable($0) })
    }
}

extension InspectorResponse {
    /// Create a response from any encodable data
    public static func success<T: Encodable>(id: String, value: T) throws -> InspectorResponse {
        // Convert Encodable to dictionary representation
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return InspectorResponse.success(id: id, data: AnyCodable(dict))
    }
}
