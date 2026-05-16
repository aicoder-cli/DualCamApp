//
//  DualCamApp.swift
//  DualCamApp
//
//  应用入口
//

import SwiftUI

@main
struct DualCamApp: App {
    @AppStorage("hasCompletedQuickStartOnboarding") private var hasCompletedQuickStartOnboarding = false
    @AppStorage(SettingsKey.appLanguageCode) private var appLanguageCode = AppLanguage.system.rawValue

    init() {
        AppSettings.migrateIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedQuickStartOnboarding {
                    ContentView()
                } else {
                    QuickStartOnboardingView {
                        hasCompletedQuickStartOnboarding = true
                    }
                }
            }
            .environment(\.locale, AppLanguage.from(appLanguageCode).locale)
            .statusBar(hidden: true)
            .preferredColorScheme(.dark)
        }
    }
}
