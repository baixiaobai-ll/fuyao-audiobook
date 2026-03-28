// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AIAudioBook",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "AIAudioBook",
            targets: ["AIAudioBook"]
        ),
        .executable(
            name: "AI有声书App",
            targets: ["AI有声书App"]
        ),
    ],
    dependencies: [
        // 如果需要可以添加第三方依赖
        // .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.8.0"),
    ],
    targets: [
        .target(
            name: "AIAudioBook",
            dependencies: [],
            path: "Sources",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "AI有声书App",
            dependencies: ["AIAudioBook"],
            path: "App",
            resources: [.process("../Config.plist")]
        ),
        .testTarget(
            name: "AIAudioBookTests",
            dependencies: ["AIAudioBook"],
            path: "Tests"
        ),
    ]
)
