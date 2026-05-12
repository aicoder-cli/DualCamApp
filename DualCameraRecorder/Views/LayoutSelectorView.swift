//
//  LayoutSelectorView.swift
//  DualCameraRecorder
//
//  布局选择器视图 - 提供预设布局选择界面（清新风格）
//

import SwiftUI

// MARK: - 布局选择器视图

struct LayoutSelectorView: View {
    
    @ObservedObject var layoutManager: LayoutManager
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("选择布局")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 30, height: 30)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            
            if isExpanded {
                // 布局选项网格
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
                .frame(maxHeight: 280)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
    }
}

// MARK: - 布局选项卡片

struct LayoutOptionCard: View {
    
    let layout: LayoutType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // 布局图标
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            isSelected
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                : AnyShapeStyle(Color.white.opacity(0.08))
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: layout.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                }
                
                // 布局名称
                Text(layout.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                    .lineLimit(1)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.06 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected
                            ? Color.blue.opacity(0.5)
                            : Color.clear,
                        lineWidth: 1.5
                    )
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
            VStack(spacing: 5) {
                // 图标容器
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            isSelected
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [Color.blue.opacity(0.6), Color.cyan.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                : AnyShapeStyle(Color.white.opacity(0.08))
                        )
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: layout.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
                
                Text(layout.rawValue)
                    .font(.system(size: 10, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white.opacity(0.95) : .white.opacity(0.5))
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - 底部布局工具栏

struct LayoutToolbar: View {
    
    @ObservedObject var layoutManager: LayoutManager
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
            .padding(.horizontal, 16)
        }
        .frame(height: 68)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            Rectangle()
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - 布局预览小窗口

struct LayoutPreviewMini: View {
    
    let layout: LayoutType
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.gray.opacity(0.2)
                
                switch layout {
                case .pictureInPicture:
                    Color.blue.opacity(0.4)
                    Color.cyan.opacity(0.5)
                        .frame(width: geometry.size.width * 0.35, height: geometry.size.height * 0.35)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .position(x: geometry.size.width * 0.75, y: geometry.size.height * 0.7)
                    
                case .sideBySide:
                    HStack(spacing: 1) {
                        Color.cyan.opacity(0.5)
                        Color.blue.opacity(0.4)
                    }
                    
                case .topBottom:
                    VStack(spacing: 1) {
                        Color.blue.opacity(0.4)
                        Color.cyan.opacity(0.5)
                    }
                    
                case .diagonal:
                    ZStack {
                        Color.gray.opacity(0.15)
                        Color.blue.opacity(0.4)
                            .frame(width: geometry.size.width * 0.4, height: geometry.size.height * 0.4)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .position(x: geometry.size.width * 0.75, y: geometry.size.height * 0.7)
                        Color.cyan.opacity(0.5)
                            .frame(width: geometry.size.width * 0.4, height: geometry.size.height * 0.4)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .position(x: geometry.size.width * 0.25, y: geometry.size.height * 0.3)
                    }
                    
                case .focusBack:
                    ZStack {
                        Color.blue.opacity(0.4)
                        Color.cyan.opacity(0.5)
                            .frame(width: geometry.size.width * 0.3, height: geometry.size.height * 0.3)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .position(x: geometry.size.width * 0.2, y: geometry.size.height * 0.2)
                    }
                    
                case .focusFront:
                    ZStack {
                        Color.cyan.opacity(0.5)
                        Color.blue.opacity(0.4)
                            .frame(width: geometry.size.width * 0.3, height: geometry.size.height * 0.3)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .position(x: geometry.size.width * 0.8, y: geometry.size.height * 0.8)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(width: 60, height: 45)
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

// MARK: - AnyShapeStyle 兼容包装

private struct AnyShapeStyle: ShapeStyle {
    
    private let _resolve: (inout ShapeStyleResolver) -> Void
    
    init<S: ShapeStyle>(_ style: S) {
        _resolve = style.resolve
    }
    
    func resolve(in environment: EnvironmentValues, to shapeStyleResolver: inout ShapeStyleResolver) {
        _resolve(&shapeStyleResolver)
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
