// MARK: - Example Integration
// This file shows how to integrate RealmInspector into your iOS app.
// Copy the relevant parts to your project.

/*
 
 ================================================================================
 EXAMPLE 1: SwiftUI App with AppDelegate
 ================================================================================
 
 // AppDelegate.swift
 
 import UIKit
 import RealmSwift
 
 #if DEBUG
 import RealmInspector
 #endif
 
 class AppDelegate: UIResponder, UIApplicationDelegate {
     
     func application(
         _ application: UIApplication,
         didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
     ) -> Bool {
         
         // Configure Realm
         let config = Realm.Configuration(
             schemaVersion: 1,
             migrationBlock: { migration, oldSchemaVersion in
                 // Handle migrations
             }
         )
         Realm.Configuration.defaultConfiguration = config
         
         // Start RealmInspector in DEBUG builds
         #if DEBUG
         startRealmInspector()
         #endif
         
         return true
     }
     
     #if DEBUG
     private func startRealmInspector() {
         // Option 1: Use default Realm
         RealmInspector.shared.start()
         
         // Option 2: Use specific Realm
         // if let realm = try? Realm() {
         //     RealmInspector.shared.start(realm: realm)
         // }
         
         // Optional: Set up callbacks
         RealmInspector.shared.onClientConnect = { clientId in
             print("RealmCompass connected: \(clientId)")
         }
         
         RealmInspector.shared.onError = { error in
             print("RealmInspector error: \(error)")
         }
     }
     #endif
 }
 
 ================================================================================
 EXAMPLE 2: Pure SwiftUI App
 ================================================================================
 
 // MyApp.swift
 
 import SwiftUI
 import RealmSwift
 
 #if DEBUG
 import RealmInspector
 #endif
 
 @main
 struct MyApp: SwiftUI.App {
     
     init() {
         configureRealm()
         
         #if DEBUG
         RealmInspector.shared.start()
         #endif
     }
     
     var body: some Scene {
         WindowGroup {
             ContentView()
         }
     }
     
     private func configureRealm() {
         let config = Realm.Configuration(schemaVersion: 1)
         Realm.Configuration.defaultConfiguration = config
     }
 }
 
 ================================================================================
 EXAMPLE 3: Using the View Modifier
 ================================================================================
 
 // ContentView.swift
 
 import SwiftUI
 
 #if DEBUG
 import RealmInspector
 #endif
 
 struct ContentView: View {
     var body: some View {
         NavigationStack {
             List {
                 // Your content
             }
             .navigationTitle("My App")
         }
         #if DEBUG
         .realmInspector()  // Starts inspector when view appears
         #endif
     }
 }
 
 ================================================================================
 EXAMPLE 4: With Status Indicator Overlay
 ================================================================================
 
 // MainView.swift
 
 import SwiftUI
 
 #if DEBUG
 import RealmInspector
 #endif
 
 struct MainView: View {
     var body: some View {
         ZStack(alignment: .topTrailing) {
             // Main content
             TabView {
                 HomeView()
                     .tabItem { Label("Home", systemImage: "house") }
                 
                 SettingsView()
                     .tabItem { Label("Settings", systemImage: "gear") }
             }
             
             // Debug overlay
             #if DEBUG
             RealmInspectorStatusView()
                 .padding(.top, 50)
                 .padding(.trailing, 16)
             #endif
         }
     }
 }
 
 ================================================================================
 EXAMPLE 5: For Iris - Integrating with your existing setup
 ================================================================================
 
 // In your Iris app, you likely have a RealmManager or similar.
 // Here's how to integrate:
 
 import Foundation
 import RealmSwift
 
 #if DEBUG
 import RealmInspector
 #endif
 
 class RealmManager {
     static let shared = RealmManager()
     
     private(set) var realm: Realm!
     
     private init() {
         configureRealm()
         
         #if DEBUG
         startInspector()
         #endif
     }
     
     private func configureRealm() {
         var config = Realm.Configuration()
         
         // Your existing Realm configuration
         config.schemaVersion = 5
         config.migrationBlock = { migration, oldVersion in
             // Your migrations
         }
         
         // For Sync (if using MongoDB Realm Sync)
         // config.syncConfiguration = ...
         
         do {
             realm = try Realm(configuration: config)
         } catch {
             fatalError("Failed to open Realm: \(error)")
         }
     }
     
     #if DEBUG
     private func startInspector() {
         // Start with your configured Realm
         RealmInspector.shared.start(realm: realm)
         
         // Log connection events
         RealmInspector.shared.onClientConnect = { _ in
             print("📱 RealmCompass connected - you can now inspect Iris's database!")
         }
     }
     #endif
     
     // Your existing methods...
     func getGames() -> Results<Game> {
         return realm.objects(Game.self)
     }
     
     func getPlayers() -> Results<Player> {
         return realm.objects(Player.self)
     }
 }
 
 ================================================================================
 EXAMPLE 6: Conditional Compilation for App Store
 ================================================================================
 
 // To ensure RealmInspector is NEVER included in release builds,
 // you can also use build settings:
 
 // 1. In your Package.swift or Xcode project, only link RealmInspector for Debug
 
 // Package.swift example:
 // .target(
 //     name: "MyApp",
 //     dependencies: [
 //         .product(name: "RealmSwift", package: "realm-swift"),
 //     ],
 //     // Only include RealmInspector in debug
 //     conditionalDependencies: [
 //         .when(configuration: .debug): [
 //             .product(name: "RealmInspector", package: "RealmInspector")
 //         ]
 //     ]
 // )
 
 // 2. Or use Swift compiler flags in Xcode:
 //    - Go to Build Settings
 //    - Find "Other Swift Flags"
 //    - Add -DDEBUG for Debug configuration only
 
 */

// MARK: - Sample Realm Models (for testing)

import Foundation
import RealmSwift

/// Sample User model for testing
class SampleUser: Object {
    @Persisted(primaryKey: true) var _id: ObjectId
    @Persisted var name: String = ""
    @Persisted var email: String = ""
    @Persisted var age: Int = 0
    @Persisted var createdAt: Date = Date()
    @Persisted var isActive: Bool = true
    @Persisted var settings: SampleSettings?
    @Persisted var tags: List<String>
}

/// Sample embedded settings object
class SampleSettings: EmbeddedObject {
    @Persisted var notificationsEnabled: Bool = true
    @Persisted var theme: String = "dark"
    @Persisted var language: String = "en"
}

/// Sample Game model (similar to what you'd have in Iris)
class SampleGame: Object {
    @Persisted(primaryKey: true) var _id: ObjectId
    @Persisted var name: String = ""
    @Persisted var startTime: Date = Date()
    @Persisted var endTime: Date?
    @Persisted var status: String = "pending"
    @Persisted var players: List<SamplePlayer>
    @Persisted var scores: Map<String, Int>
}

/// Sample Player model
class SamplePlayer: Object {
    @Persisted(primaryKey: true) var _id: ObjectId
    @Persisted var username: String = ""
    @Persisted var score: Int = 0
    @Persisted var team: String = ""
    @Persisted var joinedAt: Date = Date()
}
