//
//  Photo2driveApp.swift
//  Photo2drive
//

import SwiftUI
import GoogleSignIn

@main
struct Photo2driveApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // CloudStorageManagerで全てのOAuthコールバックを処理
                    _ = CloudStorageManager.shared.handleURL(url)
                }
        }
    }
}
