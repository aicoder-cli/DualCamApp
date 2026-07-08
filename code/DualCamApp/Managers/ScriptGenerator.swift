//
//  ScriptGenerator.swift
//  DualCamApp
//
//  AI 字幕生成服务
//

import Foundation

@MainActor
class ScriptGenerator: ObservableObject {

    @Published var isGenerating = false
    @Published var errorMessage: String?

    private let sceneTemplates: [String: [String]] = [
        NSLocalizedString("script.scene.product", comment: ""): [
            NSLocalizedString("script.product.1", comment: ""),
            NSLocalizedString("script.product.2", comment: ""),
            NSLocalizedString("script.product.3", comment: ""),
            NSLocalizedString("script.product.4", comment: ""),
            NSLocalizedString("script.product.5", comment: ""),
            NSLocalizedString("script.product.6", comment: ""),
            NSLocalizedString("script.product.7", comment: ""),
            NSLocalizedString("script.product.8", comment: "")
        ],
        NSLocalizedString("script.scene.teaching", comment: ""): [
            NSLocalizedString("script.teaching.1", comment: ""),
            NSLocalizedString("script.teaching.2", comment: ""),
            NSLocalizedString("script.teaching.3", comment: ""),
            NSLocalizedString("script.teaching.4", comment: ""),
            NSLocalizedString("script.teaching.5", comment: ""),
            NSLocalizedString("script.teaching.6", comment: ""),
            NSLocalizedString("script.teaching.7", comment: ""),
            NSLocalizedString("script.teaching.8", comment: "")
        ],
        NSLocalizedString("script.scene.vlog", comment: ""): [
            NSLocalizedString("script.vlog.1", comment: ""),
            NSLocalizedString("script.vlog.2", comment: ""),
            NSLocalizedString("script.vlog.3", comment: ""),
            NSLocalizedString("script.vlog.4", comment: ""),
            NSLocalizedString("script.vlog.5", comment: ""),
            NSLocalizedString("script.vlog.6", comment: ""),
            NSLocalizedString("script.vlog.7", comment: ""),
            NSLocalizedString("script.vlog.8", comment: "")
        ],
        NSLocalizedString("script.scene.food", comment: ""): [
            NSLocalizedString("script.food.1", comment: ""),
            NSLocalizedString("script.food.2", comment: ""),
            NSLocalizedString("script.food.3", comment: ""),
            NSLocalizedString("script.food.4", comment: ""),
            NSLocalizedString("script.food.5", comment: ""),
            NSLocalizedString("script.food.6", comment: ""),
            NSLocalizedString("script.food.7", comment: ""),
            NSLocalizedString("script.food.8", comment: "")
        ],
        NSLocalizedString("script.scene.travel", comment: ""): [
            NSLocalizedString("script.travel.1", comment: ""),
            NSLocalizedString("script.travel.2", comment: ""),
            NSLocalizedString("script.travel.3", comment: ""),
            NSLocalizedString("script.travel.4", comment: ""),
            NSLocalizedString("script.travel.5", comment: ""),
            NSLocalizedString("script.travel.6", comment: ""),
            NSLocalizedString("script.travel.7", comment: ""),
            NSLocalizedString("script.travel.8", comment: "")
        ]
    ]

    func generateScript(topic: String, style: String) async -> TeleprompterScript? {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        try? await Task.sleep(nanoseconds: 1_200_000_000)

        if let template = sceneTemplates[style] {
            let content = template.joined(separator: "\n")
            return TeleprompterScript(
                title: topic.isEmpty ? style : topic,
                content: content,
                source: .aiGenerated
            )
        }

        let lines = [
            String(format: NSLocalizedString("script.generic.1", comment: ""), topic),
            NSLocalizedString("script.generic.2", comment: ""),
            NSLocalizedString("script.generic.3", comment: ""),
            NSLocalizedString("script.generic.4", comment: ""),
            NSLocalizedString("script.generic.5", comment: ""),
            NSLocalizedString("script.generic.6", comment: ""),
            NSLocalizedString("script.generic.7", comment: ""),
            NSLocalizedString("script.generic.8", comment: "")
        ]
        return TeleprompterScript(
            title: topic,
            content: lines.joined(separator: "\n"),
            source: .aiGenerated
        )
    }

    var availableScenes: [String] {
        Array(sceneTemplates.keys).sorted()
    }
}
