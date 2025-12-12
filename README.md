# RealmInspector SDK

A Swift package that enables real-time inspection of Realm databases on iOS devices from a companion macOS desktop app (RealmCompass).

## Features

- **Schema Introspection** - View all Realm object types and their properties
- **Document Browsing** - Query and view documents with filtering and pagination
- **Live Editing** - Create, update, and delete documents
- **Real-time Updates** - Subscribe to changes and see updates live
- **Zero Configuration** - Automatic discovery via Bonjour

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/obe711/RealmSwift-Inspector-SDK.git", from: "1.0.0")
]
```

Or in Xcode: File → Add Package Dependencies → Enter the repository URL.

## Usage

### Basic Setup

```swift
#if DEBUG
// Both Wi-Fi and USB (default)
RealmInspector.shared.start()

// USB only (faster, no network needed)
RealmInspector.shared.start(transportMode: .usbOnly)

// Wi-Fi only
RealmInspector.shared.start(transportMode: .networkOnly)

// Custom ports
RealmInspector.shared.start(networkPort: 9876, usbPort: 9877)
#endif
```

Add RealmInspector to your app in DEBUG builds only:

```swift
import SwiftUI
import RealmSwift

#if DEBUG
import RealmInspector
#endif

@main
struct MyApp: App {

    init() {
        #if DEBUG
        // Start with default Realm
        RealmInspector.shared.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### With a Specific Realm

```swift
#if DEBUG
let config = Realm.Configuration(/* your config */)
let realm = try! Realm(configuration: config)
RealmInspector.shared.start(realm: realm)
#endif
```

### SwiftUI View Modifier

```swift
struct ContentView: View {
    var body: some View {
        NavigationView {
            // Your content
        }
        #if DEBUG
        .realmInspector()
        #endif
    }
}
```

### Custom Port

```swift
RealmInspector.shared.start(port: 9999)
```

### Connection Callbacks

```swift
RealmInspector.shared.onClientConnect = { clientId in
    print("Desktop connected: \(clientId)")
}

RealmInspector.shared.onClientDisconnect = { clientId in
    print("Desktop disconnected: \(clientId)")
}
```

### Status Indicator (iOS)

Add a floating indicator to show connection status:

```swift
struct ContentView: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Your content

            #if DEBUG
            RealmInspectorStatusView()
                .padding()
            #endif
        }
    }
}
```

## iOS Configuration

### Required Info.plist Entries

For iOS 14+, you must add these entries to your app's Info.plist to allow Bonjour advertising:

**NSLocalNetworkUsageDescription** - Required permission description:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>RealmInspector needs local network access to allow debugging connections from the desktop companion app.</string>
```

**NSBonjourServices** - Declares the service type:

```xml
<key>NSBonjourServices</key>
<array>
    <string>_realminspector._tcp</string>
</array>
```

Without these entries:

- Bonjour advertising will silently fail
- Desktop clients won't discover your device
- The permission prompt won't appear

### Adding Entries Only for DEBUG Builds (Recommended)

Since RealmInspector is development-only, you can automatically add these entries only to DEBUG builds using a build phase script:

1. In Xcode, select your app target
2. Go to **Build Phases** tab
3. Click **"+"** → **"New Run Script Phase"**
4. Paste this script:

```bash
if [ "${CONFIGURATION}" == "Debug" ]; then
    INFO_PLIST="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"

    # Add NSLocalNetworkUsageDescription
    /usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string 'RealmInspector needs local network access to allow debugging connections from the desktop companion app.'" "$INFO_PLIST" 2>/dev/null || true

    # Add NSBonjourServices array
    /usr/libexec/PlistBuddy -c "Add :NSBonjourServices array" "$INFO_PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :NSBonjourServices:0 string '_realminspector._tcp'" "$INFO_PLIST" 2>/dev/null || true

    echo "Added RealmInspector Info.plist entries for DEBUG configuration"
fi
```

5. **Important**: Drag the new script phase to run **after** the "Copy Bundle Resources" phase
6. Build your app in DEBUG - the entries will be automatically added to the built Info.plist

This approach keeps your source Info.plist clean and ensures these entries never appear in Release builds.

### Troubleshooting Error -72008 on Device

If you get `Failed to publish Bonjour service. Error code: -72008` on a physical device but not the simulator:

**1. Verify entries are in the built app:**

```bash
# After building, check the actual Info.plist in your built app:
plutil -p ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug-iphoneos/YourApp.app/Info.plist | grep -A 5 "NSLocalNetworkUsageDescription\|NSBonjourServices"
```

If the keys are missing, the build script didn't run or the entries weren't added to your source Info.plist.

**2. Check local network permission:**

- Go to **Settings** → **Privacy & Security** → **Local Network**
- Find your app in the list
- Ensure the toggle is **ON**

If your app isn't in the list, `NSLocalNetworkUsageDescription` is missing from the built Info.plist.

**3. Verify build script ran:**

- Open Xcode's **Report Navigator** (⌘9)
- Select your latest build
- Look for "Added RealmInspector Info.plist entries for DEBUG configuration" in the script phase output

**4. Check configuration name:**
If your Debug configuration has a custom name (e.g., "Development"), update the script:

```bash
if [ "${CONFIGURATION}" == "Development" ]; then  # Use your actual config name
```

**5. Force clean and rebuild:**

```bash
# In Xcode: Product → Clean Build Folder (Shift+⌘K)
# Then rebuild
```

The simulator doesn't enforce local network privacy restrictions, which is why it works there but fails on device.

## Architecture

```
RealmInspector/
├── RealmInspector.swift      # Main entry point (singleton)
├── Protocol/
│   ├── Message.swift         # Request/Response types
│   └── MessageCoder.swift    # Wire format encoding
├── Introspection/
│   ├── SchemaExtractor.swift # Reads Realm schema
│   ├── ObjectSerializer.swift# Converts objects to JSON
│   └── QueryExecutor.swift   # Executes queries
├── Transport/
│   └── BonjourAdvertiser.swift# Network discovery
├── Server/
│   ├── InspectorServer.swift # Main server
│   ├── ClientConnection.swift# Per-client handling
│   └── RequestHandler.swift  # Request processing
└── Utilities/
    └── AnyCodable.swift      # Type-erased JSON
```

## Protocol Reference

### Request Types

| Type             | Description           | Parameters                                                           |
| ---------------- | --------------------- | -------------------------------------------------------------------- |
| `ping`           | Health check          | -                                                                    |
| `getRealmInfo`   | Get Realm metadata    | -                                                                    |
| `listSchemas`    | List all object types | -                                                                    |
| `getSchema`      | Get type details      | `typeName`                                                           |
| `queryDocuments` | Query with pagination | `typeName`, `filter?`, `sortKeyPath?`, `ascending?`, `limit`, `skip` |
| `getDocument`    | Get single document   | `typeName`, `primaryKey`                                             |
| `countDocuments` | Count matching docs   | `typeName`, `filter?`                                                |
| `createDocument` | Create new document   | `typeName`, `data`                                                   |
| `updateDocument` | Update document       | `typeName`, `primaryKey`, `changes`                                  |
| `deleteDocument` | Delete document       | `typeName`, `primaryKey`                                             |
| `subscribe`      | Watch for changes     | `typeName`, `filter?`                                                |
| `unsubscribe`    | Stop watching         | `subscriptionId`                                                     |

### Wire Format

Messages are length-prefixed JSON:

```
[4 bytes: length (big-endian)] [JSON payload]
```

Message envelope:

```json
{
  "type": "request|response|notification",
  "payload": { ... }
}
```

## Security Considerations

**RealmInspector is for development only.**

- Only include in DEBUG builds
- Uses unencrypted communication
- No authentication required
- Exposes full database access

The SDK is designed to be completely excluded from release builds using `#if DEBUG` guards.

## Requirements

- iOS 14.0+ / macOS 12.0+
- Swift 5.9+
- Realm Swift 10.45.0+

## Troubleshooting

### Device Not Discovered

1. **iOS only**: Verify Info.plist has `NSLocalNetworkUsageDescription` and `NSBonjourServices` (see iOS Configuration section above)
2. Ensure both devices are on the same network
3. Check that no firewall is blocking port 9876
4. Verify the inspector is running: `RealmInspector.shared.isRunning`

### Connection Drops

- Check for network interruptions
- Verify Realm isn't being closed elsewhere in your app
- Check console for error messages

### Slow Performance

- Large binary properties (Data) are truncated for preview
- Reduce `limit` in queries for large datasets
- Consider filtering to reduce result size
