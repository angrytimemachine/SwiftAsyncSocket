//
//  SwiftAsyncSocketTests.swift
//  SwiftAsyncSocketTests
//
//  Created by Joel Saltzman on 1/10/16.
//  Copyright © 2016 Joel Saltzman. All rights reserved.
//

import XCTest
@testable import SwiftAsyncSocket

class SwiftAsyncSocketTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    func setRef(inout d : NSMutableData) {
        let preBufferSize = 10
        let preBuffer = UnsafeMutablePointer<Int>.alloc(preBufferSize);
        for i in 0..<preBufferSize {
            preBuffer[i] = i
        }
        d = NSMutableData.init()
        d.appendBytes(preBuffer, length: preBufferSize)
    }
    
    func testSocket() {
        
//        let socketName = "SocketName.Here"
//        let socketQueue  = dispatch_queue_create(socketName, nil);
//        var mself = self
//        withUnsafeMutablePointer(&mself) { v in
//            dispatch_queue_set_specific(socketQueue, socketName, v, nil);
//        }
        
        var d : NSMutableData = NSMutableData.init()
        print("before: \(d)")
        setRef(&d)
        print("after: \(d)")
        
//        if dispatch_get_specific(socketName) != nil {
//            print("found it")
//            
//        } else {
//            print("didn't find it")
//        }
    }
    
    func testExample() {
//        let server = GCDAsyncSocket.init()
//        server.IPv6Enabled = true
//        var d  = NSMutableData.init()
//        let wp = GCDAsyncWritePacket.init(withData: d, timeout: 1, tag: 1)
//        wp.buffer.appendBytes(d.bytes, length: d.length)
        
        let cc : CInt = 1
        let ci : CInt = 1
        print("sizeof CUnsignedChar \(sizeof(CUnsignedChar)) CInt \(sizeof(CInt))")
        print("sizeofValue cc \(sizeofValue(cc)) ci \(sizeofValue(ci))")
        print("strideof CUnsignedChar \(strideof(CUnsignedChar)) CInt \(strideof(CInt))")
        
        let preBufferSize = 10
        let preBuffer = UnsafeMutablePointer<Int>.alloc(preBufferSize);
        for i in 0..<preBufferSize {
            preBuffer[i] = i
        }
        let readPointer = preBuffer
        var writePointer = preBuffer
        print("available: \(writePointer.memory - readPointer.memory)")
        
        //write 5s to first half
        for i in 0..<5 {
            print("before (\(i)): \(writePointer[i])")
            writePointer[i] = 5
            print("after (\(i)): \(writePointer[i])")
        }
        //move it to second half
        writePointer += 5
        for i in 0..<5 {
            print("current (\(i)): \(writePointer[i])")
        }
        
        let newBuffer = UnsafeMutablePointer<Int>.alloc(preBufferSize);
        for i in 0..<preBufferSize {
            newBuffer[i] = 0
        }
        for i in 0..<preBufferSize {
            print("\(i): \(newBuffer[i])")
        }
        newBuffer.advancedBy(50).assignFrom(writePointer, count: 5)
        print("assignBackwardFrom")
        for i in 0..<preBufferSize {
            print("\(i): \(newBuffer[i])")
        }
        
        //Is this the right way? Is there another way to do it?
//        let newBufferSize = preBufferSize + 15
//        let newBuffer = UnsafeMutablePointer<Int>.alloc(newBufferSize)
//        newBuffer.initializeFrom(preBuffer, count: preBufferSize)
//        for i in 0..<newBufferSize {
//            print("newB: \(newBuffer[i])")
//        }
        
        
        
//        let d = preBuffer.advancedBy(2)
//        for i in 0..<preBufferSize {
//            d[i] = i*10
//        }
        
//        for i in 0..<preBufferSize {
//            if i < preBufferSize - 2{
//                print("p: \(preBuffer[i]) d: \(d[i])")
//            }else{
//                print("p: \(preBuffer[i])")
//            }
//        }
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock {
//            var bytes = [Int]()//fast but unsafe?
//            let data = NSMutableData.init()//slow
//            let ptr = UnsafeMutablePointer<Int>.alloc(1)
//            let preBuffer = UnsafeMutableBufferPointer<Int>(start: ptr, count: 1)
//            for i in 0..<9999999 {
//                ptr.memory += i;
//                bytes.append(i)
//                var val = UnsafePointer<Int>(bitPattern: i)
//                data.appendBytes(&val, length: sizeofValue(val))
            
            
//                let count = 9999999
//                let array = UnsafeMutablePointer<Int>.alloc(count)
//                for a in 0..<count {
//                    array[a] = Int(arc4random())
//                }
//                print("\(_stdlib_getDemangledTypeName(array))");
//
//                // Sort
//                for _ in 0..<count {
//                    for j in 0..<count - 1 {
//                        if array[j] > array[j + 1] {
//                            swap(&array[j], &array[j + 1])}
//                    }
//                }
//                array.dealloc(count)
            
//                    var array = Array(count: count, repeatedValue: 0)
//                    for i in 0..<count {
//                        array[i] = Int(arc4random())
//                    }
//                    // Sort
//                    for _ in 0..<count {
//                        for j in 0..<count - 1 {
//                            if array[j] > array[j + 1] {
//                                swap(&array[j], &array[j + 1])
//                            }
//                        }
//                    }
            

            
            
//            }
        }
    }
//    int *num;
//    num = malloc(10 * sizeof(int));
//    for (int i = 0; i < 10; i++) {
//    num[i] = i;
//    }
    
}
