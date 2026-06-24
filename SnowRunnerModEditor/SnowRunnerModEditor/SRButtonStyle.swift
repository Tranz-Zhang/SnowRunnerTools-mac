import SwiftUI

struct SRButtonStyle: ButtonStyle {
    enum ColorStyle {
        case main
        case subtle
        case normal
        case destructive
        case green
    }

    enum Size {
        case regular
        case small

        var font: Font {
            switch self {
            case .regular:
                return .callout.weight(.semibold)
            case .small:
                return .caption.weight(.semibold)
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular:
                return 18
            case .small:
                return 12
            }
        }

        var minHeight: CGFloat {
            switch self {
            case .regular:
                return 44
            case .small:
                return 30
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .regular:
                return 14
            case .small:
                return 9
            }
        }
    }

    @Environment(\.isEnabled) private var isEnabled
    var colorStyle: ColorStyle = .subtle
    var size: Size = .regular
    var minWidth: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, size.horizontalPadding)
            .frame(minWidth: minWidth, minHeight: size.minHeight)
            .background {
                RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
                    .fill(backgroundStyle)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
                    .stroke(borderStyle)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundStyle: Color {
        switch colorStyle {
            case .main:
                return .white
            case .subtle:
                return .accentColor
            case .normal:
                return Color(nsColor: .darkGray)
            case .destructive:
                return .red
            case .green:
                return .green
        }
    }
    
    private var backgroundStyle: Color {
        switch colorStyle {
            case .main:
                return Color(white: 0.2)
            case .subtle:
                return .accentColor.opacity(0.12)
            case .normal:
                return .white
            case .destructive:
                return .red.opacity(0.05)
            case .green:
                return .green.opacity(0.05)
        }
    }
    
    private var borderStyle: Color {
        switch colorStyle {
            case .main:
                return .clear
            case .subtle:
                return .accentColor.opacity(0.24)
            case .normal:
                return Color(nsColor: .lightGray).opacity(0.5)
            case .destructive:
                return .red
            case .green:
                return .green
        }
    }
}
