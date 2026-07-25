import SwiftUI

@main
struct TagLibSwiftDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 640, minHeight: 720)
                #endif
        }
    }
}
