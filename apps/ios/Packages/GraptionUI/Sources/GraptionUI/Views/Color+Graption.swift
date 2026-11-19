import SwiftUI

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    // Pine Peach palette, matching the logo.
    public static let graptionBackground = Color(hex: 0x1D3A3A)
    public static let graptionBubble = Color(hex: 0x264A4A)
    public static let graptionAccent = Color(hex: 0xFBE6D4)
    public static let graptionPeach = Color(hex: 0xE8A07E)
    public static let graptionSecondaryText = Color(hex: 0x93CDC1)
}
