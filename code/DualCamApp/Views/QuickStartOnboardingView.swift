import SwiftUI

struct LaunchIntroView: View {
    let onComplete: () -> Void
    @State private var markOpacity = 0.0
    @State private var markScale = 0.88
    @State private var slashOffset: CGFloat = -150
    @State private var slashOpacity = 0.0
    @State private var titleOpacity = 0.0
    @State private var titleOffset: CGFloat = 14

    var body: some View {
        ZStack {
            QuickStartDesign.background
                .ignoresSafeArea()

            RadialGradient(
                colors: [QuickStartDesign.accent.opacity(0.24), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 360
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Text("DC")
                        .font(.system(size: 72, weight: .black, design: .rounded))
                        .kerning(-6)
                        .foregroundColor(QuickStartDesign.accent)
                        .scaleEffect(markScale)
                        .opacity(markOpacity)

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(QuickStartDesign.accent)
                        .frame(width: 7, height: 160)
                        .rotationEffect(.degrees(14))
                        .shadow(color: QuickStartDesign.accent.opacity(0.38), radius: 18, x: 0, y: 0)
                        .offset(x: slashOffset)
                        .opacity(slashOpacity)
                }
                .frame(width: 190, height: 160)

                VStack(spacing: 8) {
                    Text("DualCam")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .kerning(-1.6)
                        .foregroundColor(.white)

                    Text("onboarding.hero.subtitle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(QuickStartDesign.mutedText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .opacity(titleOpacity)
                .offset(y: titleOffset)
                .padding(.horizontal, 36)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: runAnimation)
    }

    private func runAnimation() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            markOpacity = 1
            markScale = 1
        }
        withAnimation(.easeOut(duration: 0.58).delay(0.24)) {
            slashOffset = 0
            slashOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.42).delay(0.62)) {
            titleOpacity = 1
            titleOffset = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
            withAnimation(.easeInOut(duration: 0.28)) {
                onComplete()
            }
        }
    }
}

struct QuickStartOnboardingView: View {
    let onComplete: () -> Void
    @State private var isShowingLaunchIntro = true

    private let cards: [QuickStartCard] = [
        QuickStartCard(
            icon: "camera",
            titleKey: "onboarding.card.dualCamera.title",
            bodyKey: "onboarding.card.dualCamera.body"
        ),
        QuickStartCard(
            icon: "square.grid.2x2",
            titleKey: "onboarding.card.layouts.title",
            bodyKey: "onboarding.card.layouts.body"
        ),
        QuickStartCard(
            icon: "record.circle",
            titleKey: "onboarding.card.record.title",
            bodyKey: "onboarding.card.record.body"
        )
    ]

    var body: some View {
        ZStack {
            QuickStartDesign.background
                .ignoresSafeArea()

            RadialGradient(
                colors: [QuickStartDesign.accent.opacity(0.28), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 360
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.white.opacity(0.10), .clear],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 460
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    hero

                    VStack(spacing: 12) {
                        ForEach(cards) { card in
                            QuickStartCardView(card: card)
                        }
                    }

                    permissionsCard

                    Button(action: onComplete) {
                        HStack(spacing: 10) {
                            Text("onboarding.start")
                                .font(.system(size: 18, weight: .black))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 17, weight: .black))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(QuickStartDesign.accent)
                                .shadow(color: QuickStartDesign.accent.opacity(0.32), radius: 20, x: 0, y: 10)
                        )
                    }
                    .buttonStyle(QuickStartPressButtonStyle())

                    Text("onboarding.permissions.manageLater")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(QuickStartDesign.mutedText)
                }
                .padding(.horizontal, 24)
                .padding(.top, 76)
                .padding(.bottom, 36)
            }

            if isShowingLaunchIntro {
                LaunchIntroView {
                    isShowingLaunchIntro = false
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: isShowingLaunchIntro)
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(QuickStartDesign.accent)
                    .frame(width: 92, height: 92)
                    .shadow(color: QuickStartDesign.accent.opacity(0.32), radius: 24, x: 0, y: 12)

                HStack(spacing: 9) {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 22, height: 22)
                    Circle()
                        .fill(Color.black)
                        .frame(width: 22, height: 22)
                }
                .offset(y: -8)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.30), lineWidth: 2)
                    .frame(width: 72, height: 58)
                    .offset(y: 10)
            }

            VStack(spacing: 10) {
                Text("onboarding.hero.title")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("onboarding.hero.subtitle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(QuickStartDesign.mutedText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(QuickStartDesign.accent)

                Text("onboarding.permissions.title")
                    .font(.system(size: 17, weight: .black))
                    .foregroundColor(.white)
            }

            Text("onboarding.permissions.body")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(QuickStartDesign.mutedText)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(QuickStartDesign.accent.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct QuickStartCard: Identifiable {
    let id = UUID()
    let icon: String
    let titleKey: LocalizedStringKey
    let bodyKey: LocalizedStringKey
}

private struct QuickStartCardView: View {
    let card: QuickStartCard

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: card.icon)
                .font(.system(size: 20, weight: .black))
                .foregroundColor(.black)
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(QuickStartDesign.accent)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(card.titleKey)
                    .font(.system(size: 17, weight: .black))
                    .foregroundColor(.white)

                Text(card.bodyKey)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(QuickStartDesign.mutedText)
                    .lineSpacing(3)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.13), lineWidth: 1)
        )
    }
}

private struct QuickStartPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private enum QuickStartDesign {
    static let background = Color(red: 0.02, green: 0.024, blue: 0.032)
    static let accent = Color(red: 0.84, green: 1.0, blue: 0.30)
    static let mutedText = Color.white.opacity(0.62)
}
