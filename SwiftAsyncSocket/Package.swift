import PackageDescription
//make sure to remove the existing CIfaddrs module.modulemap file before building on linux
let package = Package(
    name: "SwiftAsyncSocket",
    targets: [],
    dependencies: [.Package(url: "https://github.com/saltzmanjoelh/CIfaddrs", majorVersion: 1),
                   .Package(url: "https://github.com/saltzmanjoelh/Dispatch", versions:Version(1,0,1)...Version(1,0,1))]
)
