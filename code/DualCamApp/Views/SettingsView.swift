import SwiftUI

struct SettingsView: View {
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var layoutManager: LayoutManager
    @Binding var defaultLivePhotoDuration: Double
    @Binding var shootingFrameRate: Int

    @AppStorage(SettingsKey.appLanguageCode) private var appLanguageCode = AppLanguage.system.rawValue
    @AppStorage(SettingsKey.defaultCaptureMode) private var defaultCaptureModeRaw = DefaultCaptureMode.video.rawValue
    @AppStorage(SettingsKey.defaultLayout) private var defaultLayoutRaw = LayoutType.pictureInPicture.rawValue
    @AppStorage(SettingsKey.rememberLastLayout) private var rememberLastLayout = true
    @AppStorage(SettingsKey.photoAspectRatio) private var photoAspectRatioRaw = PhotoAspectRatio.threeByFour.rawValue
    @AppStorage(SettingsKey.videoResolution) private var videoResolutionRaw = VideoResolution.p1080.rawValue
    @AppStorage(SettingsKey.videoCodec) private var videoCodecRaw = VideoCodec.h264.rawValue
    @AppStorage(SettingsKey.immersiveRecording) private var immersiveRecording = true
    @AppStorage(SettingsKey.controlRevealSeconds) private var controlRevealSeconds = ControlRevealDuration.twoSeconds.rawValue
    @AppStorage(SettingsKey.recordingCountdownSeconds) private var recordingCountdownSeconds = RecordingCountdown.off.rawValue
    @AppStorage(SettingsKey.soundAndHapticsEnabled) private var soundAndHapticsEnabled = true
    @AppStorage(SettingsKey.keepOriginalStreams) private var keepOriginalStreams = false
    @AppStorage(SettingsKey.workNamingRule) private var workNamingRuleRaw = WorkNamingRule.dateLayout.rawValue
    @AppStorage(SettingsKey.autoClearCache) private var autoClearCache = false
    @Environment(\.dismiss) private var dismiss

    private var mediaOutputSpec: MediaOutputSpec {
        MediaOutputSpec(
            photoAspectRatio: PhotoAspectRatio.from(photoAspectRatioRaw),
            videoResolution: VideoResolution.from(videoResolutionRaw),
            frameRate: shootingFrameRate,
            videoCodec: VideoCodec.from(videoCodecRaw)
        )
    }

    var body: some View {
        NavigationView {
            SettingsBackground {
                VStack(spacing: 0) {
                    SettingsTopBar(titleKey: "DualCam", trailingTitleKey: "settings.done") {
                        dismiss()
                    }

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            SettingsHero(titleKey: "settings.title", subtitleKey: "settings.subtitle")
                            shootingDefaultsSection
                            videoPhotoSection
                            recordingExperienceSection
                            worksStorageSection
                            aboutSection
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 28)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .accentColor(SettingsPalette.accent)
    }

    private var shootingDefaultsSection: some View {
        SettingsSectionCard(titleKey: "settings.section.shootingDefaults", footerKey: "settings.appliesNextSession") {
            SettingsNavigationRow(
                titleKey: "settings.language.title",
                subtitleKey: "settings.language.footer",
                value: AnyView(Text(AppLanguage.from(appLanguageCode).titleKey))
            ) {
                SettingsStringOptionDetailView(
                    titleKey: "settings.language.title",
                    subtitleKey: "settings.language.footer",
                    selection: $appLanguageCode,
                    options: AppLanguage.allCases,
                    rawValue: { $0.rawValue },
                    titleKeyForOption: { $0.titleKey },
                    descriptionKeyForOption: { _ in nil }
                )
            }

            SettingsNavigationRow(
                titleKey: "settings.defaultCaptureMode.title",
                subtitleKey: "settings.defaultCaptureMode.subtitle",
                value: AnyView(Text(DefaultCaptureMode.from(defaultCaptureModeRaw).titleKey))
            ) {
                SettingsStringOptionDetailView(
                    titleKey: "settings.defaultCaptureMode.title",
                    subtitleKey: "settings.defaultCaptureMode.subtitle",
                    selection: $defaultCaptureModeRaw,
                    options: DefaultCaptureMode.allCases,
                    rawValue: { $0.rawValue },
                    titleKeyForOption: { $0.titleKey },
                    descriptionKeyForOption: { $0.descriptionKey }
                )
            }

            SettingsNavigationRow(
                titleKey: "settings.defaultLayout.title",
                subtitleKey: "settings.defaultLayout.subtitle",
                value: AnyView(Text(LayoutType.from(defaultLayoutRaw).shortTitleKey))
            ) {
                SettingsStringOptionDetailView(
                    titleKey: "settings.defaultLayout.title",
                    subtitleKey: "settings.defaultLayout.subtitle",
                    selection: $defaultLayoutRaw,
                    options: LayoutType.allCases,
                    rawValue: { $0.rawValue },
                    titleKeyForOption: { $0.titleKey },
                    descriptionKeyForOption: { $0.descriptionKey }
                )
            }

            SettingsSwitchRow(
                titleKey: "settings.rememberLastLayout.title",
                subtitleKey: "settings.rememberLastLayout.subtitle",
                isOn: $rememberLastLayout
            )
        }
    }

    private var videoPhotoSection: some View {
        SettingsSectionCard(titleKey: "settings.section.videoPhoto", footerKey: "settings.appliesNextRecording") {
            SettingsNavigationRow(
                titleKey: "settings.mediaOutput.title",
                subtitleKey: "settings.mediaOutput.subtitle",
                value: AnyView(Text(mediaOutputSpec.settingsSummaryText))
            ) {
                MediaOutputDetailView(
                    photoAspectRatioRaw: $photoAspectRatioRaw,
                    videoResolutionRaw: $videoResolutionRaw,
                    videoCodecRaw: $videoCodecRaw,
                    defaultLivePhotoDuration: $defaultLivePhotoDuration,
                    shootingFrameRate: $shootingFrameRate,
                    effectiveFrameRate: cameraManager.effectiveFrameRate,
                    nativeOutputStatus: cameraManager.nativeOutputStatus
                )
            }

            SettingsStaticValueRow(
                titleKey: "settings.effectiveFrameRate",
                subtitleKey: "settings.effectiveFrameRate.subtitle"
            ) {
                Text("\(cameraManager.effectiveFrameRate) fps")
            }
        }
    }

    private var recordingExperienceSection: some View {
        SettingsSectionCard(titleKey: "settings.section.recordingExperience", footerKey: "settings.appliesNextRecording") {
            SettingsSwitchRow(
                titleKey: "settings.immersiveRecording.title",
                subtitleKey: "settings.immersiveRecording.subtitle",
                isOn: $immersiveRecording
            )

            SettingsNavigationRow(
                titleKey: "settings.controlRevealTime.title",
                subtitleKey: "settings.controlRevealTime.subtitle",
                value: AnyView(Text(ControlRevealDuration.from(controlRevealSeconds).titleKey))
            ) {
                SettingsIntOptionDetailView(
                    titleKey: "settings.controlRevealTime.title",
                    subtitleKey: "settings.controlRevealTime.subtitle",
                    selection: $controlRevealSeconds,
                    options: ControlRevealDuration.allCases,
                    rawValue: { $0.rawValue },
                    titleKeyForOption: { $0.titleKey },
                    descriptionKeyForOption: { $0.descriptionKey }
                )
            }

            SettingsNavigationRow(
                titleKey: "settings.recordingCountdown.title",
                subtitleKey: "settings.recordingCountdown.subtitle",
                value: AnyView(Text(RecordingCountdown.from(recordingCountdownSeconds).titleKey))
            ) {
                SettingsIntOptionDetailView(
                    titleKey: "settings.recordingCountdown.title",
                    subtitleKey: "settings.recordingCountdown.subtitle",
                    selection: $recordingCountdownSeconds,
                    options: RecordingCountdown.allCases,
                    rawValue: { $0.rawValue },
                    titleKeyForOption: { $0.titleKey },
                    descriptionKeyForOption: { $0.descriptionKey }
                )
            }

            SettingsSwitchRow(
                titleKey: "settings.soundHaptics.title",
                subtitleKey: "settings.soundHaptics.subtitle",
                isOn: $soundAndHapticsEnabled
            )
        }
    }

    private var worksStorageSection: some View {
        SettingsSectionCard(titleKey: "settings.section.worksStorage") {
            SettingsStaticValueRow(
                titleKey: "settings.saveToSystemPhotos.title",
                subtitleKey: "settings.saveToSystemPhotos.subtitle"
            ) {
                Text("settings.manualSaveOnly")
            }

            SettingsSwitchRow(
                titleKey: "settings.keepOriginalStreams.title",
                subtitleKey: "settings.keepOriginalStreams.subtitle",
                isOn: $keepOriginalStreams
            )

            SettingsNavigationRow(
                titleKey: "settings.workNamingRule.title",
                subtitleKey: "settings.workNamingRule.subtitle",
                value: AnyView(Text(WorkNamingRule.from(workNamingRuleRaw).titleKey))
            ) {
                SettingsStringOptionDetailView(
                    titleKey: "settings.workNamingRule.title",
                    subtitleKey: "settings.workNamingRule.subtitle",
                    selection: $workNamingRuleRaw,
                    options: WorkNamingRule.allCases,
                    rawValue: { $0.rawValue },
                    titleKeyForOption: { $0.titleKey },
                    descriptionKeyForOption: { $0.descriptionKey }
                )
            }

            SettingsSwitchRow(
                titleKey: "settings.autoClearCache.title",
                subtitleKey: "settings.autoClearCache.subtitle",
                isOn: $autoClearCache
            )
        }
    }

    private var aboutSection: some View {
        SettingsSectionCard(titleKey: "settings.section.about") {
            SettingsNavigationRow(
                titleKey: "settings.about.title",
                subtitleKey: nil,
                value: AnyView(Text(appVersionText))
            ) {
                SettingsAboutDetailView(version: appVersionText)
            }
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

private enum SettingsURL {
    static let feedback = URL(string: "https://dualcam.pages.dev/feedback")!
    static let privacy = URL(string: "https://dualcam.pages.dev/privacy")!
    static let terms = URL(string: "https://dualcam.pages.dev/terms")!
}

private enum SettingsPalette {
    static let background = Color(red: 0.02, green: 0.024, blue: 0.032)
    static let accent = Color(red: 0.84, green: 1.0, blue: 0.30)
    static let card = Color.white.opacity(0.07)
    static let stroke = Color.white.opacity(0.08)
    static let divider = Color.white.opacity(0.07)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.52)
    static let tertiaryText = Color.white.opacity(0.34)
}

private struct SettingsBackground<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            SettingsPalette.background.ignoresSafeArea()
            RadialGradient(
                colors: [SettingsPalette.accent.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 320
            )
            .ignoresSafeArea()
            content()
        }
        .preferredColorScheme(.dark)
    }
}

private struct SettingsTopBar: View {
    let titleKey: LocalizedStringKey
    let trailingTitleKey: LocalizedStringKey
    let trailingAction: () -> Void

    var body: some View {
        HStack {
            Color.clear.frame(width: 56, height: 44)
            Spacer()
            Text(titleKey)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(SettingsPalette.primaryText)
            Spacer()
            Button(action: trailingAction) {
                Text(trailingTitleKey)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SettingsPalette.accent)
                    .frame(minWidth: 56, minHeight: 44, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(SettingsPalette.background.opacity(0.94))
    }
}

private struct SettingsHero: View {
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titleKey)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .kerning(-1.8)
                .foregroundColor(SettingsPalette.primaryText)
            Text(subtitleKey)
                .font(.system(size: 12, weight: .medium))
                .lineSpacing(2)
                .foregroundColor(SettingsPalette.secondaryText)
        }
        .padding(.top, 8)
        .padding(.horizontal, 2)
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let titleKey: LocalizedStringKey
    let footerKey: LocalizedStringKey?
    @ViewBuilder let content: () -> Content

    init(titleKey: LocalizedStringKey, footerKey: LocalizedStringKey? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.titleKey = titleKey
        self.footerKey = footerKey
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(titleKey)
                .font(.system(size: 11, weight: .black))
                .kerning(1.4)
                .textCase(.uppercase)
                .foregroundColor(SettingsPalette.accent)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }

            if let footerKey {
                Text(footerKey)
                    .font(.system(size: 11, weight: .medium))
                    .lineSpacing(2)
                    .foregroundColor(SettingsPalette.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(SettingsPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(SettingsPalette.stroke, lineWidth: 1)
        )
    }
}

private struct SettingsNavigationRow<Destination: View>: View {
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey?
    let value: AnyView
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination()) {
            SettingsRowContent(titleKey: titleKey, subtitleKey: subtitleKey, value: value, showsChevron: true)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsStaticValueRow<Value: View>: View {
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey?
    @ViewBuilder let value: () -> Value

    var body: some View {
        SettingsRowContent(
            titleKey: titleKey,
            subtitleKey: subtitleKey,
            value: AnyView(value()),
            showsChevron: false
        )
    }
}

private struct SettingsSwitchRow: View {
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey?
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isOn.toggle()
            }
        } label: {
            SettingsRowContent(
                titleKey: titleKey,
                subtitleKey: subtitleKey,
                value: AnyView(SettingsToggle(isOn: isOn)),
                showsChevron: false
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MediaOutputDetailView: View {
    @Binding var photoAspectRatioRaw: String
    @Binding var videoResolutionRaw: String
    @Binding var videoCodecRaw: String
    @Binding var defaultLivePhotoDuration: Double
    @Binding var shootingFrameRate: Int
    let effectiveFrameRate: Int32
    let nativeOutputStatus: NativeOutputStatus
    @Environment(\.dismiss) private var dismiss

    private var mediaOutputSpec: MediaOutputSpec {
        MediaOutputSpec(
            photoAspectRatio: PhotoAspectRatio.from(photoAspectRatioRaw),
            videoResolution: VideoResolution.from(videoResolutionRaw),
            frameRate: shootingFrameRate,
            videoCodec: VideoCodec.from(videoCodecRaw)
        )
    }

    private var nativeOutputStatusText: String {
        switch nativeOutputStatus {
        case .pending:
            return L10n.string("settings.mediaOutput.fallback.pending")
        case .ready:
            return L10n.string("settings.mediaOutput.fallback.ready")
        case .fallback(let reason):
            return reason
        }
    }

    var body: some View {
        SettingsBackground {
            VStack(spacing: 0) {
                SettingsDetailTopBar(dismiss: dismiss)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        SettingsHero(titleKey: "settings.mediaOutput.title", subtitleKey: "settings.mediaOutput.subtitle")

                        SettingsSectionCard(titleKey: "settings.mediaOutput.effective") {
                            SettingsStaticValueRow(titleKey: "settings.mediaOutput.effective", subtitleKey: nil) {
                                Text(mediaOutputSpec.settingsSummaryText)
                            }
                            SettingsStaticValueRow(titleKey: "settings.mediaOutput.format", subtitleKey: "settings.videoCodec.subtitle") {
                                Text("settings.mediaOutput.format.compatible")
                            }
                            SettingsStaticValueRow(titleKey: "settings.mediaOutput.fallback", subtitleKey: nil) {
                                Text(nativeOutputStatusText)
                            }
                        }

                        SettingsSectionCard(titleKey: "settings.section.videoPhoto") {
                            SettingsNavigationRow(
                                titleKey: "settings.photoAspectRatio.title",
                                subtitleKey: "settings.photoAspectRatio.subtitle",
                                value: AnyView(Text(PhotoAspectRatio.from(photoAspectRatioRaw).titleKey))
                            ) {
                                SettingsStringOptionDetailView(
                                    titleKey: "settings.photoAspectRatio.title",
                                    subtitleKey: "settings.photoAspectRatio.subtitle",
                                    selection: $photoAspectRatioRaw,
                                    options: PhotoAspectRatio.allCases,
                                    rawValue: { $0.rawValue },
                                    titleKeyForOption: { $0.titleKey },
                                    descriptionKeyForOption: { $0.descriptionKey }
                                )
                            }

                            SettingsNavigationRow(
                                titleKey: "settings.videoResolution.title",
                                subtitleKey: "settings.videoResolution.subtitle",
                                value: AnyView(Text(VideoResolution.from(videoResolutionRaw).titleKey))
                            ) {
                                SettingsStringOptionDetailView(
                                    titleKey: "settings.videoResolution.title",
                                    subtitleKey: "settings.videoResolution.subtitle",
                                    selection: $videoResolutionRaw,
                                    options: VideoResolution.allCases,
                                    rawValue: { $0.rawValue },
                                    titleKeyForOption: { $0.titleKey },
                                    descriptionKeyForOption: { $0.descriptionKey }
                                )
                            }

                            SettingsNavigationRow(
                                titleKey: "settings.frameRate.title",
                                subtitleKey: "settings.frameRate.subtitle",
                                value: AnyView(Text("\(shootingFrameRate) fps"))
                            ) {
                                SettingsFrameRateDetailView(selection: $shootingFrameRate)
                            }

                            SettingsStaticValueRow(
                                titleKey: "settings.effectiveFrameRate",
                                subtitleKey: "settings.effectiveFrameRate.subtitle"
                            ) {
                                Text("\(effectiveFrameRate) fps")
                            }

                            SettingsStaticValueRow(
                                titleKey: "settings.mediaOutput.liveCanvas",
                                subtitleKey: "settings.livePhotoDuration.subtitle"
                            ) {
                                Text("settings.mediaOutput.liveCanvas.followPhoto")
                            }

                            SettingsNavigationRow(
                                titleKey: "settings.livePhotoDuration.title",
                                subtitleKey: "settings.livePhotoDuration.subtitle",
                                value: AnyView(Text(LivePhotoDurationOption.from(seconds: defaultLivePhotoDuration).titleKey))
                            ) {
                                SettingsLivePhotoDurationDetailView(selection: $defaultLivePhotoDuration)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

private struct SettingsAboutDetailView: View {
    let version: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsBackground {
            VStack(spacing: 0) {
                SettingsDetailTopBar(dismiss: dismiss)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        SettingsAboutCard(version: version)

                        VStack(spacing: 0) {
                            SettingsAboutLinkRow(titleKey: "settings.about.feedback") {
                                openURL(SettingsURL.feedback)
                            }
                            SettingsAboutLinkRow(titleKey: "settings.about.privacy") {
                                openURL(SettingsURL.privacy)
                            }
                            SettingsAboutLinkRow(titleKey: "settings.about.terms") {
                                openURL(SettingsURL.terms)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(SettingsPalette.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(SettingsPalette.stroke, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

private struct SettingsAboutLinkRow: View {
    let titleKey: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(titleKey)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SettingsPalette.primaryText)
                Spacer(minLength: 12)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(SettingsPalette.accent)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 54)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(SettingsPalette.divider)
                    .frame(height: 1)
                    .padding(.leading, 14)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsRowContent: View {
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey?
    let value: AnyView
    let showsChevron: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titleKey)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SettingsPalette.primaryText)
                if let subtitleKey {
                    Text(subtitleKey)
                        .font(.system(size: 11, weight: .medium))
                        .lineSpacing(1)
                        .foregroundColor(SettingsPalette.secondaryText)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                value
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SettingsPalette.primaryText.opacity(0.64))
                    .lineLimit(1)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(SettingsPalette.tertiaryText)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 54)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SettingsPalette.divider)
                .frame(height: 1)
                .padding(.leading, 14)
        }
    }
}

private struct SettingsToggle: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isOn ? SettingsPalette.accent : Color.white.opacity(0.18))
            .frame(width: 46, height: 28)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? SettingsPalette.background : Color.white)
                    .frame(width: 22, height: 22)
                    .padding(3)
            }
    }
}

private struct SettingsStringOptionDetailView<Option: Identifiable>: View {
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey?
    @Binding var selection: String
    let options: [Option]
    let rawValue: (Option) -> String
    let titleKeyForOption: (Option) -> LocalizedStringKey
    let descriptionKeyForOption: (Option) -> LocalizedStringKey?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsOptionScreen(titleKey: titleKey, subtitleKey: subtitleKey, dismiss: dismiss) {
            ForEach(options) { option in
                SettingsOptionButton(
                    titleKey: titleKeyForOption(option),
                    descriptionKey: descriptionKeyForOption(option),
                    isSelected: selection == rawValue(option)
                ) {
                    selection = rawValue(option)
                }
            }
        }
    }
}

private struct SettingsIntOptionDetailView<Option: Identifiable>: View {
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey?
    @Binding var selection: Int
    let options: [Option]
    let rawValue: (Option) -> Int
    let titleKeyForOption: (Option) -> LocalizedStringKey
    let descriptionKeyForOption: (Option) -> LocalizedStringKey?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsOptionScreen(titleKey: titleKey, subtitleKey: subtitleKey, dismiss: dismiss) {
            ForEach(options) { option in
                SettingsOptionButton(
                    titleKey: titleKeyForOption(option),
                    descriptionKey: descriptionKeyForOption(option),
                    isSelected: selection == rawValue(option)
                ) {
                    selection = rawValue(option)
                }
            }
        }
    }
}

private struct SettingsFrameRateDetailView: View {
    @Binding var selection: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsOptionScreen(titleKey: "settings.frameRate.title", subtitleKey: "settings.frameRate.subtitle", dismiss: dismiss) {
            ForEach(ShootingFrameRate.allCases) { option in
                SettingsOptionButton(
                    title: option.title,
                    descriptionKey: option.subtitleKey,
                    isSelected: selection == option.rawValue
                ) {
                    selection = option.rawValue
                }
            }
        }
    }
}

private struct SettingsLivePhotoDurationDetailView: View {
    @Binding var selection: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsOptionScreen(titleKey: "settings.livePhotoDuration.title", subtitleKey: "settings.livePhotoDuration.subtitle", dismiss: dismiss) {
            ForEach(LivePhotoDurationOption.allCases) { option in
                SettingsOptionButton(
                    titleKey: option.titleKey,
                    descriptionKey: option.descriptionKey,
                    isSelected: LivePhotoDurationOption.from(seconds: selection) == option
                ) {
                    selection = option.seconds
                }
            }
        }
    }
}

private struct SettingsOptionScreen<Content: View>: View {
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey?
    let dismiss: DismissAction
    @ViewBuilder let content: () -> Content

    var body: some View {
        SettingsBackground {
            VStack(spacing: 0) {
                SettingsDetailTopBar(dismiss: dismiss)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        SettingsHero(titleKey: titleKey, subtitleKey: subtitleKey ?? "")
                        VStack(spacing: 10) {
                            content()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 28)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

private struct SettingsDetailTopBar: View {
    let dismiss: DismissAction

    var body: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                    Text("settings.title")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(SettingsPalette.accent)
                .frame(minHeight: 44)
            }

            Spacer()

            Text("DualCam")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(SettingsPalette.primaryText)

            Spacer()
            Color.clear.frame(width: 76, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(SettingsPalette.background.opacity(0.94))
    }
}

private struct SettingsOptionButton: View {
    let title: String?
    let titleKey: LocalizedStringKey?
    let descriptionKey: LocalizedStringKey?
    let isSelected: Bool
    let action: () -> Void

    init(title: String, descriptionKey: LocalizedStringKey?, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.titleKey = nil
        self.descriptionKey = descriptionKey
        self.isSelected = isSelected
        self.action = action
    }

    init(titleKey: LocalizedStringKey, descriptionKey: LocalizedStringKey?, isSelected: Bool, action: @escaping () -> Void) {
        self.title = nil
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if let title {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                    } else if let titleKey {
                        Text(titleKey)
                            .font(.system(size: 14, weight: .semibold))
                    }

                    if let descriptionKey {
                        Text(descriptionKey)
                            .font(.system(size: 11, weight: .medium))
                            .lineSpacing(1)
                            .foregroundColor(SettingsPalette.secondaryText)
                    }
                }
                .foregroundColor(SettingsPalette.primaryText)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(SettingsPalette.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? SettingsPalette.accent.opacity(0.11) : SettingsPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? SettingsPalette.accent.opacity(0.62) : SettingsPalette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsAboutCard: View {
    let version: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("DualCam")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .kerning(-1.2)
                    .foregroundColor(SettingsPalette.primaryText)
                Text("settings.about.description")
                    .font(.system(size: 12, weight: .medium))
                    .lineSpacing(2)
                    .foregroundColor(SettingsPalette.secondaryText)
                Text(version)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(SettingsPalette.accent)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(SettingsPalette.stroke, lineWidth: 1)
        )
    }
}
