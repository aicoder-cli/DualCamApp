//
//  TeleprompterScript.swift
//  DualCamApp
//
//  提词器字幕数据模型
//

import Foundation

enum ScriptSource: String, Codable {
    case manual
    case aiGenerated
}

struct TeleprompterScript: Identifiable, Codable {
    let id: UUID
    var title: String
    var content: String
    var source: ScriptSource
    var createdAt: Date

    init(id: UUID = UUID(), title: String, content: String, source: ScriptSource, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.source = source
        self.createdAt = createdAt
    }

    var lines: [String] {
        content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

@MainActor
class TeleprompterManager: ObservableObject {

    @Published var scripts: [TeleprompterScript] = []
    @Published var currentScript: TeleprompterScript?
    @Published var isScrolling = false
    @Published var scrollSpeed: Double = 1.0
    @Published var fontSize: Double = 24.0
    @Published var currentLineIndex: Int = 0
    @Published var showTeleprompter = false

    private let userDefaultsKey = "savedTeleprompterScripts_v2"

    init() {
        loadScripts()
    }

    func addScript(_ script: TeleprompterScript) {
        scripts.append(script)
        saveScripts()
    }

    func deleteScript(_ script: TeleprompterScript) {
        scripts.removeAll { $0.id == script.id }
        if currentScript?.id == script.id {
            currentScript = nil
        }
        saveScripts()
    }

    func selectScript(_ script: TeleprompterScript) {
        currentScript = script
        currentLineIndex = 0
    }

    func startScrolling() {
        isScrolling = true
    }

    func pauseScrolling() {
        isScrolling = false
    }

    func reset() {
        currentLineIndex = 0
        isScrolling = false
    }

    func nextLine() {
        guard let script = currentScript else { return }
        let totalLines = script.lines.count
        if currentLineIndex < totalLines - 1 {
            currentLineIndex += 1
        } else {
            isScrolling = false
        }
    }

    private func saveScripts() {
        if let encoded = try? JSONEncoder().encode(scripts) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    private func loadScripts() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([TeleprompterScript].self, from: data) else {
            scripts = [
                TeleprompterScript(
                    title: NSLocalizedString("teleprompter.welcome.title", comment: ""),
                    content: NSLocalizedString("teleprompter.welcome.content", comment: ""),
                    source: .manual
                )
            ]
            return
        }
        scripts = decoded
    }
}
