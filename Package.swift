// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AgentMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentMonitorCore", targets: ["AgentMonitorCore"])
    ],
    targets: [
        .target(name: "AgentMonitorCore"),
        .testTarget(name: "AgentMonitorCoreTests", dependencies: ["AgentMonitorCore"])
    ]
)
