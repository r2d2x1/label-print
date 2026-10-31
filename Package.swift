// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LabelPrint",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LabelPrint", targets: ["LabelPrint"])],
    targets: [
        .systemLibrary(name: "CLabelBackend", path: "Sources/CLabelBackend"),
        .target(name: "LabelCore"),
        .executableTarget(name: "LabelPrint", dependencies: ["LabelCore", "CLabelBackend"],
            linkerSettings: [.unsafeFlags(["-Lbackend/target/release"]),
                             .linkedLibrary("label_backend"),
                             .linkedFramework("IOKit"), .linkedFramework("Security"),
                             .linkedFramework("CoreFoundation")]),
        .executableTarget(name: "LabelCoreChecks", dependencies: ["LabelCore"], path: "Tests/LabelCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
