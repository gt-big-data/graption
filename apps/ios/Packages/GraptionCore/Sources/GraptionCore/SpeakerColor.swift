import SwiftUI

public func colorForSpeaker(_ name: String) -> Color {
    let speakerColors: [Color] = [
        Color(red: 1.0, green: 0.42, blue: 0.42),   // Red
        Color(red: 0.31, green: 0.81, blue: 0.77),  // Teal
        Color(red: 1.0, green: 0.90, blue: 0.43),   // Yellow
        Color(red: 0.65, green: 0.55, blue: 0.98),  // Violet
        Color(red: 0.49, green: 0.71, blue: 1.0),   // Blue
        Color(red: 1.0, green: 0.71, blue: 0.76),   // Pink
    ]

    guard name != "unknown" else { return .gray }
    // Tracked face IDs get sequential colors, shared with the web dashboard.
    if name.hasPrefix("f"), let number = Int(name.dropFirst()), number > 0 {
        if number <= speakerColors.count { return speakerColors[number - 1] }
        let hue = (Double(number) * 0.61803398875).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.55, brightness: 0.95)
    }
    let hash = name.utf8.reduce(0) { $0 &+ UInt32($1) }
    let index = Int(hash) % speakerColors.count
    return speakerColors[index]
}

/// A numbered label accompanies color for VoiceOver and color-blind users; no inferred names.
public func speakerLabel(_ id: String) -> String {
    if id.hasPrefix("f"), let number = Int(id.dropFirst()), number > 0 {
        return "Speaker \(number)"
    }
    return "Unknown speaker"
}
