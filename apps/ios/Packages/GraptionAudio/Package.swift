// swift-tools-version: 5.9
//
//  Package.swift
//  Graption
//
//  Created by Derek Kwong on 10/5/26.
//


import PackageDescription

let package = Package(
    name: "GraptionAudio",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "GraptionAudio",
            targets: ["GraptionAudio"]
        )
    ],
    targets: [
        .target(name: "GraptionAudio"),
        .testTarget(
            name: "GraptionAudioTests",
            dependencies: ["GraptionAudio"]
        )
    ]
)
