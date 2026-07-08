//
//  TeleprompterView.swift
//  DualCamApp
//
//  提词器滚动视图
//

import SwiftUI

struct TeleprompterView: View {

    @ObservedObject var manager: TeleprompterManager
    let screenWidth: CGFloat
    let screenHeight: CGFloat

    @State private var position: CGPoint = CGPoint(x: 200, y: 300)
    @State private var isDragging = false
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            if let script = manager.currentScript {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(Array(script.lines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: manager.fontSize, weight: index == manager.currentLineIndex ? .bold : .regular))
                                    .foregroundColor(index == manager.currentLineIndex ? Design.accent : .white)
                                    .lineSpacing(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .id(index)
                                    .opacity(index < manager.currentLineIndex ? 0.4 : 1.0)
                            }
                        }
                        .padding(.vertical, screenHeight * 0.3)
                    }
                    .onChange(of: manager.currentLineIndex) { _, newIndex in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
                .frame(width: screenWidth * 0.9, height: screenHeight * 0.38)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(0.65))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(isDragging ? 0.5 : 0.2), lineWidth: isDragging ? 2 : 1)
                )
                .position(position)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            position = value.location
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.4))
                    Text(NSLocalizedString("teleprompter.empty.title", comment: ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(width: 180, height: 100)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.5))
                )
                .position(position)
            }

            Spacer()

            controlBar
        }
        .onAppear { startAutoScroll() }
        .onDisappear { stopAutoScroll() }
        .onChange(of: manager.isScrolling) { _, scrolling in
            scrolling ? startAutoScroll() : stopAutoScroll()
        }
    }

    private var controlBar: some View {
        HStack(spacing: 16) {
            Button(action: {
                manager.isScrolling ? manager.pauseScrolling() : manager.startScrolling()
            }) {
                Image(systemName: manager.isScrolling ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            }

            Button(action: { manager.reset() }) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }

            VStack(spacing: 2) {
                Text(NSLocalizedString("teleprompter.speed", comment: ""))
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
                HStack(spacing: 6) {
                    Button(action: { manager.scrollSpeed = max(0.5, manager.scrollSpeed - 0.5) }) {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    Text("\(String(format: "%.1f", manager.scrollSpeed))x")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .frame(width: 36)
                    Button(action: { manager.scrollSpeed = min(3.0, manager.scrollSpeed + 0.5) }) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                }
            }

            VStack(spacing: 2) {
                Text(NSLocalizedString("teleprompter.fontSize", comment: ""))
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
                HStack(spacing: 6) {
                    Button(action: { manager.fontSize = max(16, manager.fontSize - 2) }) {
                        Text("A")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    Text("\(Int(manager.fontSize))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .frame(width: 28)
                    Button(action: { manager.fontSize = min(48, manager.fontSize + 2) }) {
                        Text("A")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
        .padding(.bottom, 100)
    }

    private func startAutoScroll() {
        stopAutoScroll()
        guard manager.isScrolling else { return }
        let interval = 2.0 / manager.scrollSpeed
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in manager.nextLine() }
        }
    }

    private func stopAutoScroll() {
        timer?.invalidate()
        timer = nil
    }
}
