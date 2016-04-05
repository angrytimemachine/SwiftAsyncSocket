import PackageDescription
//make sure to remove the existing CIfaddrs module.modulemap file before building on linux
#if os(Linux)
let package = Package(
    name: "SwiftAsyncSocket",
    targets: [],
    dependencies: [

                    .Package(url: "https://github.com/saltzmanjoelh/CIfaddrs", majorVersion: 1)
                   //.Package(url: "https://github.com/saltzmanjoelh/Dispatch", versions:Version(1,0,2)...Version(1,0,2))
    ]
)
#else
let package = Package(
    name: "SwiftAsyncSocket",
    targets: []
)
#endif