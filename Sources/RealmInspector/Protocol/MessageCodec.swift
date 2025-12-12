//
//  MessageCodec.swift
//  RealmInspector
//
//  Handles encoding and decoding of protocol messages with length-prefix framing
//

import Foundation

/// Errors that can occur during message encoding/decoding
public enum MessageCodecError: Error, LocalizedError {
    case encodingFailed(Error)
    case decodingFailed(Error)
    case invalidMessageFormat
    case messageTooLarge(size: Int, max: Int)
    case incompleteMessage
    
    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let error):
            return "Failed to encode message: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode message: \(error.localizedDescription)"
        case .invalidMessageFormat:
            return "Invalid message format"
        case .messageTooLarge(let size, let max):
            return "Message too large: \(size) bytes (max: \(max))"
        case .incompleteMessage:
            return "Incomplete message received"
        }
    }
}

/// Encodes and decodes protocol messages with length-prefix framing
///
/// Message format:
/// - 4 bytes: message length (big-endian UInt32)
/// - 1 byte: message type (0 = request, 1 = response, 2 = notification)
/// - N bytes: JSON payload
public final class MessageCodec {
    
    // MARK: - Constants
    
    public static let headerSize = 5  // 4 bytes length + 1 byte type
    public static let maxMessageSize = 10 * 1024 * 1024  // 10 MB
    
    public enum MessageType: UInt8 {
        case request = 0
        case response = 1
        case notification = 2
    }
    
    // MARK: - Encoder
    
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    
    // MARK: - Encoding
    
    /// Encode a request into a framed message
    public func encode(_ request: InspectorRequest) throws -> Data {
        return try encodeMessage(request, type: .request)
    }
    
    /// Encode a response into a framed message
    public func encode(_ response: InspectorResponse) throws -> Data {
        return try encodeMessage(response, type: .response)
    }
    
    /// Encode a change notification into a framed message
    public func encode(_ notification: ChangeNotification) throws -> Data {
        return try encodeMessage(notification, type: .notification)
    }
    
    private func encodeMessage<T: Encodable>(_ message: T, type: MessageType) throws -> Data {
        let jsonData: Data
        do {
            jsonData = try encoder.encode(message)
        } catch {
            throw MessageCodecError.encodingFailed(error)
        }
        
        let totalSize = Self.headerSize + jsonData.count
        guard totalSize <= Self.maxMessageSize else {
            throw MessageCodecError.messageTooLarge(size: totalSize, max: Self.maxMessageSize)
        }
        
        var framedData = Data(capacity: totalSize)
        
        // Write length (4 bytes, big-endian)
        var length = UInt32(jsonData.count + 1).bigEndian  // +1 for type byte
        withUnsafeBytes(of: &length) { framedData.append(contentsOf: $0) }
        
        // Write type (1 byte)
        framedData.append(type.rawValue)
        
        // Write JSON payload
        framedData.append(jsonData)
        
        return framedData
    }
    
    // MARK: - Decoding
    
    /// Decode a framed message, returning the type and the decoded object
    public func decode(from data: Data) throws -> DecodedMessage {
        guard data.count >= Self.headerSize else {
            throw MessageCodecError.incompleteMessage
        }
        
        // Read length
        let length = data.withUnsafeBytes { ptr -> UInt32 in
            UInt32(bigEndian: ptr.load(as: UInt32.self))
        }
        
        let expectedSize = Self.headerSize + Int(length) - 1  // -1 because length includes type byte
        guard data.count >= expectedSize else {
            throw MessageCodecError.incompleteMessage
        }
        
        // Read type
        let typeByte = data[4]
        guard let messageType = MessageType(rawValue: typeByte) else {
            throw MessageCodecError.invalidMessageFormat
        }
        
        // Extract JSON payload
        let jsonData = data.subdata(in: Self.headerSize..<expectedSize)
        
        do {
            switch messageType {
            case .request:
                let request = try decoder.decode(InspectorRequest.self, from: jsonData)
                return .request(request)
            case .response:
                let response = try decoder.decode(InspectorResponse.self, from: jsonData)
                return .response(response)
            case .notification:
                let notification = try decoder.decode(ChangeNotification.self, from: jsonData)
                return .notification(notification)
            }
        } catch {
            throw MessageCodecError.decodingFailed(error)
        }
    }
    
    /// Check if there's a complete message in the buffer and return its size
    public func messageSize(in buffer: Data) -> Int? {
        guard buffer.count >= Self.headerSize else {
            return nil
        }
        
        let length = buffer.withUnsafeBytes { ptr -> UInt32 in
            UInt32(bigEndian: ptr.load(as: UInt32.self))
        }
        
        let totalSize = Self.headerSize + Int(length) - 1
        
        if buffer.count >= totalSize {
            return totalSize
        }
        return nil
    }
}

/// Result of decoding a message
public enum DecodedMessage {
    case request(InspectorRequest)
    case response(InspectorResponse)
    case notification(ChangeNotification)
}

// MARK: - Message Buffer

/// A buffer for accumulating incoming data and extracting complete messages
public final class MessageBuffer {
    
    private var buffer = Data()
    private let codec = MessageCodec()
    
    public init() {}
    
    /// Append incoming data to the buffer
    public func append(_ data: Data) {
        buffer.append(data)
    }
    
    /// Try to extract the next complete message from the buffer
    public func nextMessage() throws -> DecodedMessage? {
        guard let messageSize = codec.messageSize(in: buffer) else {
            return nil
        }
        
        let messageData = buffer.prefix(messageSize)
        buffer = buffer.dropFirst(messageSize)
        
        return try codec.decode(from: Data(messageData))
    }
    
    /// Extract all complete messages from the buffer
    public func allMessages() throws -> [DecodedMessage] {
        var messages: [DecodedMessage] = []
        while let message = try nextMessage() {
            messages.append(message)
        }
        return messages
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
