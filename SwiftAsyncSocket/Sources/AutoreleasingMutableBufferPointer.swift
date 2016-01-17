//
//  AutoreleasingMutableBufferPointer.swift
//  SwiftAsyncSocket
//
//  Created by Joel Saltzman on 1/11/16.
//  Copyright © 2016 Joel Saltzman. All rights reserved.
//

import Foundation

public class AutoreleasingMutableBufferPointer<T> {
    public var buffer: UnsafeMutableBufferPointer<T>
    
    public init(start pointer: UnsafeMutablePointer<T>, count length: Int) {
        self.buffer = UnsafeMutableBufferPointer<T>(start: pointer, count: length)
    }
    
    public init(buffer: UnsafeMutableBufferPointer<T>) {
        self.buffer = buffer
    }
    
    deinit {
        self.buffer.baseAddress.destroy(buffer.count)
        self.buffer.baseAddress.dealloc(buffer.count)
    }
}
//public struct Data {
//    public typealias BlockType = UInt8
//    public var blocks: AutoreleasingMutableBufferPointer<BlockType>
//    public init(bytes: UnsafeMutablePointer<BlockType>, length: Int) {
//        let bytesCopy = UnsafeMutablePointer<BlockType>.alloc(length)
//        bytesCopy.initializeFrom(bytes, count: length)
//        self.blocks = AutoreleasingMutableBufferPointer<BlockType>(start: bytesCopy, count: length)
//    }
//}