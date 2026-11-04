//
//  HomeScreen.swift
//  Graption
//
//  Created by Claude on 11/03/26.
//

import SwiftUI
import GraptionUI

struct HomeScreen: View {
    @Environment(\.dismiss) private var dismiss
    var onOpenLiveCaptions: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    var body: some View {
        ZStack {
            Color.graptionBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Status bar
                HStack {
                    Text("9:41")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.graptionAccent)

                    Spacer()

                    HStack(spacing: 6) {
                        Image("cellular_signal", bundle: nil)
                            .frame(width: 18, height: 16)

                        Image("wifi", bundle: nil)
                            .frame(width: 16, height: 16)

                        Image("battery", bundle: nil)
                            .frame(width: 26, height: 16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(height: 44)

                // Main content
                ScrollView {
                    VStack(spacing: 24) {
                        // Header with brand and help
                        HStack {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.graptionAccent, lineWidth: 1)
                                        .background(Color.white.opacity(0.08))

                                    Text("G")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(Color.graptionAccent)
                                }
                                .frame(width: 40, height: 40)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Graption")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(Color.graptionAccent)

                                    Text("Home")
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundStyle(Color.graptionSecondaryText)
                                }
                            }

                            Spacer()

                            Button(action: {}) {
                                Text("Help")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.graptionAccent)
                                    .frame(minWidth: 56)
                                    .frame(height: 44)
                                    .background(Color.white.opacity(0.08))
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.graptionAccent, lineWidth: 1)
                                    )
                            }
                        }

                        // Welcome section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Welcome back")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Color.graptionAccent)

                            VStack(alignment: .leading, spacing: 0) {
                                Text("Your space for clearer conversations.")
                                    .lineSpacing(1.5 - 1)

                                Text("Choose where to begin.")
                                    .lineSpacing(1.5 - 1)
                            }
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color.graptionSecondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Destinations
                        VStack(spacing: 16) {
                            // Live captions main CTA
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Color.white.opacity(0.08)
                                            .frame(width: 40, height: 40)
                                            .cornerRadius(12)

                                        Image("closed_captions", bundle: nil)
                                            .frame(width: 24, height: 24)
                                    }

                                    Text("Live captions")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(Color.graptionAccent)

                                    Spacer()
                                }

                                Text("Follow the conversation with captions beneath each speaker.")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(Color.graptionSecondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button(action: onOpenLiveCaptions) {
                                    Text("Open live captions")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(Color.graptionBackground)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 52)
                                        .background(Color.graptionAccent)
                                        .cornerRadius(14)
                                }

                                Text("Camera stays off until you open captions.")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(Color.graptionSecondaryText)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(16)
                            .background(Color.graptionBubble)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.graptionAccent, lineWidth: 1)
                            )

                            // Secondary destinations
                            VStack(spacing: 16) {
                                DestinationCard(
                                    icon: Image("file_text", bundle: nil),
                                    title: "Transcript",
                                    description: "Read captions in a text-only view.",
                                    hasArrow: true,
                                    action: {}
                                )

                                Button(action: onOpenSettings) {
                                    DestinationCard(
                                        icon: Image("preferences", bundle: nil),
                                        title: "Connection & Preferences",
                                        description: "Set up your Mac server and tone tags.",
                                        statusIcon: Image("disconnected_indicator", bundle: nil),
                                        statusText: "Mac server · Not connected",
                                        hasArrow: true,
                                        action: {}
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

struct DestinationCard: View {
    let icon: Image
    let title: String
    let description: String
    let statusIcon: Image?
    let statusText: String?
    let hasArrow: Bool
    let action: () -> Void

    init(
        icon: Image,
        title: String,
        description: String,
        statusIcon: Image? = nil,
        statusText: String? = nil,
        hasArrow: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.statusIcon = statusIcon
        self.statusText = statusText
        self.hasArrow = hasArrow
        self.action = action
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Color.white.opacity(0.08)
                        .frame(width: 40, height: 40)
                        .cornerRadius(12)

                    icon
                        .frame(width: 22, height: 22)
                }

                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.graptionAccent)

                Spacer()

                if hasArrow {
                    Image("open_destination", bundle: nil)
                        .frame(width: 18, height: 18)
                        .rotationEffect(.degrees(180))
                }
            }

            Text(description)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.graptionSecondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let statusIcon, let statusText {
                HStack(spacing: 6) {
                    statusIcon
                        .frame(width: 6, height: 6)

                    Text(statusText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.graptionSecondaryText)

                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Color.graptionBubble)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.graptionAccent, lineWidth: 1)
        )
    }
}

#Preview {
    HomeScreen(onOpenLiveCaptions: {})
}
