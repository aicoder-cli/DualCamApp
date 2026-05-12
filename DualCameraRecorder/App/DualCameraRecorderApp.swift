//
//  DualCameraRecorderApp.swift
//  DualCameraRecorder
//
//  应用入口
//

import SwiftUI

@main
struct DualCameraRecorderApp: App {
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .statusBar(hidden: true)
                .preferredColorScheme(.dark)
        }
    }
}
