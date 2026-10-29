#if canImport(SwiftUI)
// Sources/Presentation/Design/Tokens.swift
import SwiftUI

public enum Spacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 6
    public static let m: CGFloat = 8
    public static let l: CGFloat = 12
    public static let xl: CGFloat = 16
    public static let xxl: CGFloat = 20
}

public enum Radius {
    public static let s: CGFloat = 4
    public static let m: CGFloat = 6
    public static let row: CGFloat = 8
    public static let hud: CGFloat = 16
}

public enum Layout {
    public static let logo: CGFloat = 44
    public static let logoPixel: CGFloat = 88
    public static let listPage = 400
    public static let trafficWidth: CGFloat = 80
    public static let trafficHeight: CGFloat = 40
    public static let playControl: CGFloat = 36
    public static let volumeSlider: CGFloat = 80
    public static let bitrateMenu: CGFloat = 72
    public static let hudIcon: CGFloat = 15
    public static let hairline: CGFloat = 0.5
}

public enum Palette {
    public static let live = Color(red: 180 / 255, green: 35 / 255, blue: 24 / 255)
    public static let favorite = Color(red: 157 / 255, green: 23 / 255, blue: 77 / 255)
    public static let video = Color(red: 12 / 255, green: 12 / 255, blue: 12 / 255)
    public static let ink = Color(red: 28 / 255, green: 25 / 255, blue: 21 / 255)
    public static let paper = Color(red: 247 / 255, green: 244 / 255, blue: 238 / 255)
    public static let info = Color(red: 15 / 255, green: 92 / 255, blue: 69 / 255)
    public static let warning = Color(red: 122 / 255, green: 78 / 255, blue: 0 / 255)
    public static let error = Color(red: 159 / 255, green: 29 / 255, blue: 29 / 255)
    public static let hudInk = Color.white
    public static let rowHover = Color.primary.opacity(0.08)
    public static let chip = Color.secondary.opacity(0.15)
    public static let infoWash = Color(red: 231 / 255, green: 240 / 255, blue: 234 / 255)
    public static let warningWash = Color(red: 248 / 255, green: 232 / 255, blue: 200 / 255)
    public static let errorWash = Color(red: 250 / 255, green: 226 / 255, blue: 222 / 255)

    public static func logoFallback(for name: String) -> Color {
        let choices = [live, favorite, info, warning, error]
        let hash = name.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31) &+ Int(scalar.value)
        }
        return choices[abs(hash) % choices.count]
    }
}

public enum StatusSeverity: String, Equatable, Sendable {
    case info
    case warning
    case error
}
#endif
