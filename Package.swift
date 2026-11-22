// swift-tools-version: 6.2

import PackageDescription

let usesStaticLlama = Context.environment["AIRTRANSLATE_STATIC_LLAMA"] == "1"
let llamaTarget: Target = usesStaticLlama
    ? .binaryTarget(name: "llama", path: "Release/build/static-llama/llama.xcframework")
    : .binaryTarget(
        name: "llama",
        url: "https://github.com/ggml-org/llama.cpp/releases/download/b12317/llama-b12317-xcframework.zip",
        checksum: "db87353dcfed41f2bd6474dd146fbd26ef0630d2f48c4e07a4b269f4646f7ec0"
    )
let staticLlamaLibraries: [LinkerSetting] = usesStaticLlama ? [
    .linkedFramework("Accelerate"),
    .linkedFramework("Metal"),
    .linkedLibrary("c++")
] : []

let package = Package(
    name: "AirTranslate",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "AirTranslate", targets: ["AirTranslate"])
    ],
    targets: [
        llamaTarget,
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
            ] + staticLlamaLibraries
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
