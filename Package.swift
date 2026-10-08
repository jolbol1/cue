// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cue",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Cue", targets: ["MarkdownPrompter"])],
    targets: [
        .target(name: "PrompterCore"),
        .executableTarget(name: "MarkdownPrompter", dependencies: ["PrompterCore"]),
        .executableTarget(name: "CueChecks", dependencies: ["PrompterCore"], path: "Tests/PrompterCoreTests")
    ]
)
