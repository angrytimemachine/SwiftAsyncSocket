//
//  SwiftAsyncSocketTests.swift
//  SwiftAsyncSocketTests
//
//  Created by Joel Saltzman on 2/6/16.
//  Copyright © 2016 Joel Saltzman. All rights reserved.
//

import XCTest
@testable import SwiftAsyncSocket
import ifaddrs

class SwiftAsyncSocketTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    func testSunPath() {
        let url = NSURL.init(string: "http://localhost")
        var nativeAddr = sockaddr_un()
        nativeAddr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(&nativeAddr.sun_path){
            print("copying")
            strlcpy($0, url!.fileSystemRepresentation, sizeofValue(url!.fileSystemRepresentation))
        }
        print("sun_family: \(nativeAddr.sun_path)")
    }
    func testMemoryToStructConversion() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        let iface = "lo0".cStringUsingEncoding(NSUTF8StringEncoding)
        let port:UInt16 = 3306
        var addr4:NSMutableData?
        var addrs : UnsafeMutablePointer<ifaddrs> = nil
        var cursor : UnsafeMutablePointer<ifaddrs> = nil
        if getifaddrs(&addrs) == 0 {
            cursor = addrs
            while cursor != nil {
//                let iface = "en0".utf8
                var nativeAddr4:sockaddr_in = UnsafeMutablePointer<sockaddr_in>(cursor).memory
                let name = String.fromCString(cursor.memory.ifa_name)
                print("name: \(name)")
                if strcmp(cursor.memory.ifa_name, iface!) == 0 {
                    // Name match
                    nativeAddr4.sin_port = port.bigEndian//bigEndian instead of htons
                    addr4 = NSMutableData.init(bytes:&nativeAddr4, length: sizeofValue(nativeAddr4))
                }else{
                    var ipAddressString = [CChar](count:Int(INET_ADDRSTRLEN), repeatedValue: 0)
                    let conversion = inet_ntop(AF_INET, &nativeAddr4.sin_addr, &ipAddressString, socklen_t(INET_ADDRSTRLEN))
                    print("conversion: \(String.fromCString(conversion)) ipAddressString: \(String.fromCString(ipAddressString))")
                    if conversion != nil && strcmp(ipAddressString, iface!) == 0 {
                        // IP match
                        nativeAddr4.sin_port = port.bigEndian
                    }
                }
                addr4 = NSMutableData.init(bytes:&nativeAddr4, length: sizeofValue(nativeAddr4))
                cursor = cursor.memory.ifa_next;
            }
        }
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock {
            // Put the code you want to measure the time of here.
        }
    }
    
}
