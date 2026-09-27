//
//  FTCBrandTheme.swift
//  FTCTeamHub
//
//  Wild Circuits brand colors and shared building blocks: the brand
//  mark, card background style, and the launch/loading screen.
//

import SwiftUI
import UIKit

enum FTCBrand {
    static let midnight = Color(red: 0.035, green: 0.055, blue: 0.14)
    static let navy = Color(red: 0.075, green: 0.11, blue: 0.25)
    static let blue = Color(red: 0.14, green: 0.31, blue: 0.55)
    static let cyan = Color(red: 0.16, green: 0.54, blue: 0.62)
    static let orange = Color(red: 0.73, green: 0.12, blue: 0.16)
    static let accentText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.48, blue: 0.44, alpha: 1)
            : UIColor(red: 0.73, green: 0.12, blue: 0.16, alpha: 1)
    })
    static let violet = Color(red: 0.39, green: 0.35, blue: 0.55)
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let ink = Color(uiColor: .label)
    static let secondaryInk = Color(uiColor: .secondaryLabel)
    static let line = Color(uiColor: .separator).opacity(0.45)
    static let background = midnight
}

struct FTCBrandMark: View {
    var size: CGFloat = 76

    var body: some View {
        Text("WC")
            .font(.system(size: size * 0.31, weight: .black, design: .rounded))
            .tracking(-size * 0.025)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(FTCBrand.orange, in: RoundedRectangle(cornerRadius: size * 0.2))
        .accessibilityLabel("FTC Team Hub")
    }
}

struct FTCBrandCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(FTCBrand.line.opacity(0.65), lineWidth: 0.75)
                    }
            }
    }
}

struct FTCColorPicker: View {
    @Binding var selection: AvatarColor

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(AvatarColor.allCases) { color in
                let isSelected = selection == color
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    selection = color
                } label: {
                    HStack(spacing: 9) {
                        Circle()
                            .fill(color.color)
                            .frame(width: 19, height: 19)
                            .overlay {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        Text(color.rawValue.capitalized)
                            .font(.system(.subheadline, design: .rounded,
                                          weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(
                        isSelected
                            ? FTCBrand.accentText.opacity(0.09)
                            : Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? FTCBrand.accentText : FTCBrand.line.opacity(0.7),
                                    lineWidth: isSelected ? 1.25 : 0.75)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(color.rawValue.capitalized)\(isSelected ? ", selected" : "")")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

struct FTCLoadingView: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    FTCBrandMark(size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WILD CIRCUITS")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(.secondary)
                        Text("Team workspace")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                    }
                }
                Rectangle().fill(FTCBrand.line).frame(height: 1)
                HStack(spacing: 11) {
                    ProgressView().tint(FTCBrand.orange)
                    Text("Opening team records…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 430)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
