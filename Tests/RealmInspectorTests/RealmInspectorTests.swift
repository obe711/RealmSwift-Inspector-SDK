import XCTest
@testable import RealmInspector
import RealmSwift

final class RealmInspectorTests: XCTestCase {
    
    var realm: Realm!
    
    override func setUpWithError() throws {
        // Use in-memory Realm for testing
        let config = Realm.Configuration(inMemoryIdentifier: "TestRealm")
        realm = try Realm(configuration: config)
    }
    
    override func tearDownWithError() throws {
        realm = nil
    }
    
    // MARK: - AnyCodable Tests
    
    func testAnyCodableWithPrimitives() throws {
        let intValue = AnyCodable(42)
        XCTAssertEqual(intValue.value as? Int, 42)
        
        let stringValue = AnyCodable("hello")
        XCTAssertEqual(stringValue.value as? String, "hello")
        
        let boolValue = AnyCodable(true)
        XCTAssertEqual(boolValue.value as? Bool, true)
        
        let doubleValue = AnyCodable(3.14)
        XCTAssertEqual(doubleValue.value as? Double, 3.14)
    }
    
    func testAnyCodableWithNull() throws {
        let nullValue = AnyCodable(nil)
        XCTAssertTrue(nullValue.isNull)
    }
    
    func testAnyCodableWithDictionary() throws {
        let dict: [String: Any] = ["name": "Test", "count": 5]
        let value = AnyCodable(dict)
        
        let decoded = value.dictionary
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?["name"] as? String, "Test")
        XCTAssertEqual(decoded?["count"] as? Int, 5)
    }
    
    func testAnyCodableWithArray() throws {
        let array: [Any] = [1, "two", 3.0]
        let value = AnyCodable(array)
        
        let decoded = value.array
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 3)
    }
    
    func testAnyCodableEncoding() throws {
        let value = AnyCodable(["key": "value"])
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let json = String(data: data, encoding: .utf8)
        XCTAssertTrue(json?.contains("key") ?? false)
    }
    
    // MARK: - Message Tests
    
    func testRequestCreation() throws {
        let request = InspectorRequest(type: .listSchemas)
        XCTAssertEqual(request.type, .listSchemas)
        XCTAssertNil(request.params)
        XCTAssertFalse(request.id.isEmpty)
    }
    
    func testRequestWithParams() throws {
        let request = InspectorRequest.with(.queryDocuments, params: [
            "typeName": "User",
            "limit": 10
        ])
        
        XCTAssertEqual(request.type, .queryDocuments)
        XCTAssertEqual(request.params?["typeName"]?.value as? String, "User")
        XCTAssertEqual(request.params?["limit"]?.value as? Int, 10)
    }
    
    func testResponseSuccess() throws {
        let response = InspectorResponse.success(id: "123", data: AnyCodable(["result": "ok"]))
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.id, "123")
        XCTAssertNil(response.error)
    }
    
    func testResponseFailure() throws {
        let response = InspectorResponse.failure(id: "456", error: "Something went wrong")
        XCTAssertFalse(response.success)
        XCTAssertEqual(response.id, "456")
        XCTAssertEqual(response.error, "Something went wrong")
    }
    
    // MARK: - MessageCoder Tests
    
    func testMessageEncodingDecoding() throws {
        let coder = MessageCoder()
        
        let request = InspectorRequest(type: .ping)
        let message = InspectorMessage.request(request)
        
        let encoded = try coder.encode(message)
        XCTAssertTrue(encoded.count > 4) // At least header + some data
        
        let decoded = try coder.decode(encoded)
        
        if case .request(let decodedRequest) = decoded {
            XCTAssertEqual(decodedRequest.type, .ping)
            XCTAssertEqual(decodedRequest.id, request.id)
        } else {
            XCTFail("Expected request message")
        }
    }
    
    func testStreamBuffer() throws {
        let coder = MessageCoder()
        let buffer = coder.createStreamBuffer()
        
        // Create two messages
        let msg1 = InspectorMessage.request(InspectorRequest(type: .ping))
        let msg2 = InspectorMessage.request(InspectorRequest(type: .listSchemas))
        
        let data1 = try coder.encode(msg1)
        let data2 = try coder.encode(msg2)
        
        // Add in chunks
        buffer.append(data1)
        buffer.append(data2)
        
        let messages = try buffer.extractMessages()
        XCTAssertEqual(messages.count, 2)
    }
    
    // MARK: - QueryParams Tests
    
    func testQueryParamsFromDictionary() throws {
        let params: [String: AnyCodable] = [
            "typeName": "User",
            "filter": "age > 18",
            "limit": 20,
            "skip": 10
        ]
        
        let queryParams = QueryParams.from(params: params)
        
        XCTAssertNotNil(queryParams)
        XCTAssertEqual(queryParams?.typeName, "User")
        XCTAssertEqual(queryParams?.filter, "age > 18")
        XCTAssertEqual(queryParams?.limit, 20)
        XCTAssertEqual(queryParams?.skip, 10)
    }
    
    func testQueryParamsDefaults() throws {
        let params: [String: AnyCodable] = [
            "typeName": "User"
        ]
        
        let queryParams = QueryParams.from(params: params)
        
        XCTAssertNotNil(queryParams)
        XCTAssertEqual(queryParams?.limit, 50)
        XCTAssertEqual(queryParams?.skip, 0)
        XCTAssertTrue(queryParams?.ascending ?? false)
    }
    
    // MARK: - SchemaInfo Tests
    
    func testSchemaInfoCreation() throws {
        let properties = [
            PropertyInfo(name: "_id", type: "ObjectId", isPrimaryKey: true),
            PropertyInfo(name: "name", type: "String"),
            PropertyInfo(name: "age", type: "Int", isOptional: true)
        ]
        
        let schema = SchemaInfo(
            name: "User",
            primaryKey: "_id",
            properties: properties,
            isEmbedded: false
        )
        
        XCTAssertEqual(schema.name, "User")
        XCTAssertEqual(schema.primaryKey, "_id")
        XCTAssertEqual(schema.properties.count, 3)
    }
    
    // MARK: - ChangeSet Tests
    
    func testChangeSetEmpty() throws {
        let changeSet = ChangeSet()
        XCTAssertTrue(changeSet.isEmpty)
    }
    
    func testChangeSetNotEmpty() throws {
        let changeSet = ChangeSet(insertions: [AnyCodable(["id": 1])])
        XCTAssertFalse(changeSet.isEmpty)
    }
}
