//
//  GCDAsyncSocketPreBuffer.swift
//  SwiftAsyncSocket
//
//  Created by Joel Saltzman on 1/10/16.
//  Copyright © 2016 Joel Saltzman. All rights reserved.
//

import Foundation

/**
 * A PreBuffer is used when there is more data available on the socket
 * than is being requested by current read request.
 * In this case we slurp up all data from the socket (to minimize sys calls),
 * and store additional yet unread data in a "prebuffer".
 *
 * The prebuffer is entirely drained before we read from the socket again.
 * In other words, a large chunk of data is written to the prebuffer.
 * The prebuffer is then drained via a series of one or more reads (for subsequent read request(s)).
 *
 * A ring buffer was once used for this purpose.
 * But a ring buffer takes up twice as much memory as needed (double the size for mirroring).
 * In fact, it generally takes up more than twice the needed size as everything has to be rounded up to vm_page_size.
 * And since the prebuffer is always completely drained after being written to, a full ring buffer isn't needed.
 *
 * The current design is very simple and straight-forward, while also keeping memory requirements lower.
 **/

class GCDAsyncSocketPreBuffer {
    
    var preBuffer : UnsafeMutablePointer<CInt>
    var preBufferSize : size_t = 0
    
    var readPointer : UnsafeMutablePointer<CInt>
    var writePointer : UnsafeMutablePointer<CInt>
    
    init(withCapacity numBytes : size_t) {
        preBufferSize = numBytes
        preBuffer = UnsafeMutablePointer<CInt>.alloc(preBufferSize);
        
        
        readPointer = preBuffer
        writePointer = preBuffer
    }
    deinit {
        preBuffer.dealloc(preBufferSize)
    }
    func ensureCapacityForWrite(numBytes : size_t) {
        let availableSpace = availableBytes()
        if numBytes > availableSpace {
            let additionalBytes = numBytes - availableSpace;
            
            let newPreBufferSize = preBufferSize + additionalBytes;
            let newPreBuffer = UnsafeMutablePointer<CInt>.alloc(newPreBufferSize);
            newPreBuffer.initializeFrom(preBuffer, count: preBufferSize)//TODO: this might be duplicated in the Socket class after we call ensureCapacityForWrite
            
            let readPointerOffset = readPointer - preBuffer;
            let writePointerOffset = writePointer - preBuffer;
            
            preBuffer = newPreBuffer;
            preBufferSize = newPreBufferSize;
            
            readPointer = preBuffer + readPointerOffset;
            writePointer = preBuffer + writePointerOffset;
        }
    }
    
    func readBuffer() -> UnsafeMutablePointer<CInt> {
        return readPointer
    }
    func writeBuffer() -> UnsafeMutablePointer<CInt> {
        return writePointer
    }
    
    func didRead(bytes bytesRead : size_t) {
        readPointer += bytesRead
        if readPointer == writePointer {
            // The prebuffer has been drained. Reset pointers.
            reset()
        }
    }
    func availableBytes() -> size_t {
        return writePointer - readPointer
    }
    func didWrite(bytes bytesWritten : size_t){
        writePointer += bytesWritten
    }
    func reset() {
        readPointer = preBuffer
        writePointer = preBuffer
    }
}