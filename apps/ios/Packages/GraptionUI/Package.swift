// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GraptionUI",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "GraptionUI",
            targets: ["GraptionUI"]
        )
    ],
    targets: [
        .target(
            name: "GraptionUI",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
