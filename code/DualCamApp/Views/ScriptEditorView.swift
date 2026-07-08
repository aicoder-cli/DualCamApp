//
//  ScriptEditorView.swift
//  DualCamApp
//
//  字幕编辑与 AI 生成界面
//

import SwiftUI

struct ScriptEditorView: View {

    @ObservedObject var teleprompterManager: TeleprompterManager
    @StateObject private var scriptGenerator = ScriptGenerator()

    @State private var scriptTitle = ""
    @State private var scriptContent = ""
    @State private var selectedScene = ""
    @State private var aiTopic = ""
    @State private var selectedTab = 0
    @State private var showDeleteAlert = false
    @State private var scriptToDelete: TeleprompterScript?
    @Environment(\.dismiss) var dismiss

    init(teleprompterManager: TeleprompterManager) {
        self.teleprompterManager = teleprompterManager
        let scenes = ScriptGenerator().availableScenes
        _selectedScene = State(initialValue: scenes.first ?? "")
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text(NSLocalizedString("teleprompter.tab.manual", comment: "")).tag(0)
                    Text(NSLocalizedString("teleprompter.tab.ai", comment: "")).tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                .background(Color.black)

                if selectedTab == 0 {
                    manualInputSection
                } else {
                    aiGenerateSection
                }

                savedScriptsSection
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("teleprompter.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) { dismiss() }
                        .foregroundColor(Design.accent)
                }
            }
        }
    }

    private var manualInputSection: some View {
        VStack(spacing: 12) {
            TextField(NSLocalizedString("teleprompter.titlePlaceholder", comment: ""), text: $scriptTitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )

            ZStack(alignment: .topLeading) {
                if scriptContent.isEmpty {
                    Text(NSLocalizedString("teleprompter.contentPlaceholder", comment: ""))
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)
                }
                TextEditor(text: $scriptContent)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(height: 150)
                    .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )

            Button(action: saveManualScript) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text(NSLocalizedString("teleprompter.save", comment: ""))
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Design.accent.opacity(0.7), Color.orange.opacity(0.5)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .disabled(scriptTitle.isEmpty || scriptContent.isEmpty)
            .opacity(scriptTitle.isEmpty || scriptContent.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal)
    }

    private var aiGenerateSection: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("teleprompter.selectScene", comment: ""))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(scriptGenerator.availableScenes, id: \.self) { scene in
                            Button(action: { selectedScene = scene }) {
                                Text(scene)
                                    .font(.system(size: 13, weight: selectedScene == scene ? .semibold : .regular))
                                    .foregroundColor(selectedScene == scene ? .white : .white.opacity(0.6))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(selectedScene == scene
                                                ? AnyShapeStyle(LinearGradient(
                                                    colors: [Design.accent.opacity(0.6), Color.orange.opacity(0.4)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                ))
                                                : AnyShapeStyle(Color.white.opacity(0.08))
                                            )
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(selectedScene == scene ? Design.accent.opacity(0.5) : Color.clear, lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
            }

            TextField(NSLocalizedString("teleprompter.topicPlaceholder", comment: ""), text: $aiTopic)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )

            Button(action: generateAIScript) {
                HStack {
                    if scriptGenerator.isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(scriptGenerator.isGenerating
                         ? NSLocalizedString("teleprompter.generating", comment: "")
                         : NSLocalizedString("teleprompter.generate", comment: ""))
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.7), Color.pink.opacity(0.5)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .disabled(scriptGenerator.isGenerating)

            if let error = scriptGenerator.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.horizontal)
            }
        }
        .padding(.horizontal)
    }

    private var savedScriptsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(NSLocalizedString("teleprompter.savedScripts", comment: ""))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(teleprompterManager.scripts.count)")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)

            List {
                ForEach(teleprompterManager.scripts) { script in
                    ScriptRow(script: script, isSelected: teleprompterManager.currentScript?.id == script.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            teleprompterManager.selectScript(script)
                            dismiss()
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                scriptToDelete = script
                                showDeleteAlert = true
                            } label: {
                                Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(PlainListStyle())
            .background(Color.black)
        }
        .background(Color.black)
        .alert(NSLocalizedString("teleprompter.confirmDelete", comment: ""), isPresented: $showDeleteAlert) {
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
                if let script = scriptToDelete {
                    teleprompterManager.deleteScript(script)
                }
            }
        } message: {
            Text(NSLocalizedString("teleprompter.deleteMessage", comment: ""))
        }
    }

    private func saveManualScript() {
        let script = TeleprompterScript(
            title: scriptTitle,
            content: scriptContent,
            source: .manual
        )
        teleprompterManager.addScript(script)
        teleprompterManager.selectScript(script)
        scriptTitle = ""
        scriptContent = ""
        dismiss()
    }

    private func generateAIScript() {
        Task {
            if let script = await scriptGenerator.generateScript(topic: aiTopic, style: selectedScene) {
                teleprompterManager.addScript(script)
                teleprompterManager.selectScript(script)
                dismiss()
            }
        }
    }
}

struct ScriptRow: View {
    let script: TeleprompterScript
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isSelected ? Design.accent.opacity(0.2) : Color.white.opacity(0.06))
                    .frame(width: 36, height: 36)
                Image(systemName: script.source == .aiGenerated ? "sparkles" : "text.quote")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? Design.accent : .white.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(script.title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Design.accent : .white)

                HStack(spacing: 6) {
                    Text(script.source == .aiGenerated ? "AI" : NSLocalizedString("teleprompter.manualTag", comment: ""))
                        .font(.system(size: 11))
                        .foregroundColor(script.source == .aiGenerated ? .orange.opacity(0.8) : .white.opacity(0.5))
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                    Text("\(script.lines.count) \(NSLocalizedString("teleprompter.lines", comment: ""))")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Design.accent)
                    .font(.system(size: 18))
            }
        }
        .padding(.vertical, 8)
        .background(isSelected ? Design.accent.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
    }
}
