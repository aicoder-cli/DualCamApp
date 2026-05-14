//
//  LayoutSelectorView.swift
//  DualCameraRecorder
//
//  布局选择器视图 - 提供预设布局选择界面（清新风格）
//

import SwiftUI

private enum TemplateStyle {
    static let accent = Color(red: 0.84, green: 1.0, blue: 0.30)
    static let panel = Color(red: 0.08, green: 0.09, blue: 0.10).opacity(0.88)
    static let card = Color.white.opacity(0.08)
    static let stroke = Color.white.opacity(0.14)
}

// MARK: - 布局选择器视图

struct LayoutSelectorView: View {

    @ObservedObject var layoutManager: LayoutManager
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("layout.templates")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    Text(layoutManager.currentLayout.titleKey)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TemplateStyle.accent.opacity(0.86))
                }

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(TemplateStyle.accent))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(glassPanel(cornerRadius: 20))

            if isExpanded {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(LayoutType.allCases) { layout in
                            LayoutOptionCard(
                                layout: layout,
                                isSelected: layoutManager.currentLayout == layout,
                                onTap: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        layoutManager.switchLayout(to: layout)
                                    }
                                }
                            )
                        }
                    }
                    .padding(14)
                }
                .frame(maxHeight: 300)
                .background(glassPanel(cornerRadius: 22))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)
    }

    private func glassPanel(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(TemplateStyle.stroke, lineWidth: 0.8)
            )
    }
}

// MARK: - 布局选项卡片

struct LayoutOptionCard: View {

    let layout: LayoutType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                LayoutPreviewMini(layout: layout)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Circle()
                                .fill(TemplateStyle.accent)
                                .frame(width: 9, height: 9)
                                .padding(7)
                        }
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(layout.shortTitleKey)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isSelected ? TemplateStyle.accent : .white)

                    Text(layout.titleKey)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.52))
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? TemplateStyle.accent.opacity(0.13) : TemplateStyle.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? TemplateStyle.accent.opacity(0.85) : TemplateStyle.stroke, lineWidth: isSelected ? 1.4 : 0.7)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - 快速布局切换按钮（底部工具栏用）

struct QuickLayoutButton: View {

    let layout: LayoutType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 7) {
                LayoutPreviewMini(layout: layout)
                    .frame(width: 58, height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? TemplateStyle.accent : Color.white.opacity(0.10), lineWidth: isSelected ? 1.4 : 0.6)
                    )

                Text(layout.shortTitleKey)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? TemplateStyle.accent : .white.opacity(0.54))
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - 底部布局工具栏

struct LayoutToolbar: View {

    @ObservedObject var layoutManager: LayoutManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(LayoutType.allCases) { layout in
                    QuickLayoutButton(
                        layout: layout,
                        isSelected: layoutManager.currentLayout == layout,
                        onTap: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                layoutManager.switchLayout(to: layout)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 78)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(TemplateStyle.stroke, lineWidth: 0.8)
        )
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 8)
    }
}

// MARK: - 布局预览小窗口

struct LayoutPreviewMini: View {

    let layout: LayoutType

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.02, green: 0.025, blue: 0.03))

                switch layout {
                case .splitVertical:
                    HStack(spacing: 1) {
                        cameraFill(.front)
                        cameraFill(.back)
                    }

                case .splitHorizontal:
                    VStack(spacing: 1) {
                        cameraFill(.back)
                        cameraFill(.front)
                    }

                case .pictureInPicture:
                    cameraFill(.back)
                    cameraFill(.front)
                        .frame(width: geometry.size.width * 0.36, height: geometry.size.height * 0.36)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .position(x: geometry.size.width * 0.72, y: geometry.size.height * 0.68)

                case .circleReaction:
                    cameraFill(.back)
                    cameraFill(.front)
                        .frame(width: geometry.size.width * 0.34, height: geometry.size.width * 0.34)
                        .clipShape(Circle())
                        .position(x: geometry.size.width * 0.72, y: geometry.size.height * 0.32)

                case .directorStack:
                    cameraFill(.back)
                        .frame(width: geometry.size.width * 0.66, height: geometry.size.height * 0.64)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .position(x: geometry.size.width * 0.40, y: geometry.size.height * 0.46)
                    cameraFill(.front)
                        .frame(width: geometry.size.width * 0.66, height: geometry.size.height * 0.64)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .position(x: geometry.size.width * 0.62, y: geometry.size.height * 0.56)

                case .diagonalCut:
                    cameraFill(.back)
                        .clipShape(MiniDiagonalLeadingShape())
                    cameraFill(.front)
                        .clipShape(MiniDiagonalTrailingShape())
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(width: 68, height: 48)
    }

    private func cameraFill(_ camera: CameraType) -> some View {
        LinearGradient(
            colors: camera == .front
                ? [TemplateStyle.accent.opacity(0.95), Color(red: 0.40, green: 0.95, blue: 0.72).opacity(0.72)]
                : [Color.white.opacity(0.32), Color.white.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct MiniDiagonalLeadingShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct MiniDiagonalTrailingShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 缩放按钮样式

private struct ScaleButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            LayoutSelectorView(
                layoutManager: LayoutManager(),
                isExpanded: .constant(true)
            )
            .padding()

            Spacer()

            LayoutToolbar(layoutManager: LayoutManager())
        }
    }
}
