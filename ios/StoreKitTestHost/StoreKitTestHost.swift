import SwiftUI

/// Test-only host: XCTest configures SKTestSession before constructing PlusStore.
@main
struct StoreKitTestHostApp: App {
    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
    }
}
