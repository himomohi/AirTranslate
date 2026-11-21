// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AirTranslate",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "AirTranslate", targets: ["AirTranslate"])
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b12317/llama-b12317-xcframework.zip",
            checksum: "db87353dcfed41f2bd6474dd146fbd26ef0630d2f48c4e07a4b269f4646f7ec0"
        ),
        .target(name: "AirTranslateCore"),
        .executableTarget(
            name: "AirTranslate",
            dependencies: ["AirTranslateCore", "llama"],
            linkerSettings: [
                .linkedFramework("AVFAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Security"),
                .linkedFramework("Speech"),
                .linkedFramework("Translation")
            ]
        ),
        .testTarget(
            name: "AirTranslateCoreTests",
            dependencies: [
                "AirTranslateCore",
                "AirTranslate"
            ]
        )
    ]
)
