//
//  GCDAsyncReadPacket.swift
//  SwiftAsyncSocket
//
//  Created by Joel Saltzman on 1/10/16.
//  Copyright © 2016 Joel Saltzman. All rights reserved.
//

import Foundation

/**
 * The GCDAsyncReadPacket encompasses the instructions for any given read.
 * The content of a read packet allows the code to determine if we're:
 *  - reading to a certain length
 *  - reading to a certain separator
 *  - or simply reading the first chunk of available data
 **/

class GCDAsyncReadPacket {
    var buffer: NSMutableData?
    var startOffset: Int
    var bytesDone: Int
    var maxLength: Int
    var timeout: NSTimeInterval
    var readLength: Int
    var term: NSData?
    var bufferOwner: Bool
    var originalBufferLength: Int
    var tag: Int
    
    init(withData d : NSMutableData?, startOffset s : Int, maxLength m : Int, timeout t : NSTimeInterval, readLength l : Int, terminator e : NSData, tag i : Int){
        bytesDone = 0
        maxLength = m
        timeout = t
        readLength = l
        tag = i
        startOffset = 0
        bufferOwner = true
        originalBufferLength = 0
        
        if let terminator = e.copy() as? NSData {
            term =  terminator
        } else {
            term = nil
        }
        
        if let data = d {
            buffer = data
            startOffset = s
            bufferOwner = false
            originalBufferLength = data.length
            
        } else if let b = NSMutableData.init(length: readLength > 0 ? readLength : 0){
            buffer = b
        }else{
            buffer = nil
        }
    }
    /**
    * Increases the length of the buffer (if needed) to ensure a read of the given size will fit.
    **/
    func ensureCapacityForAdditionalDataOfLength(bytesToRead:Int){
        if let b = buffer {
            let buffSize: Int = b.length
            let buffUsed: Int = startOffset + bytesDone
            let buffSpace: Int = buffSize - buffUsed
            if bytesToRead > buffSpace {
                let buffInc: Int = bytesToRead - buffSpace
                buffer?.increaseLengthBy(buffInc)
            }
        }

    }
    /**
    * This method is used when we do NOT know how much data is available to be read from the socket.
    * This method returns the default value unless it exceeds the specified readLength or maxLength.
    *
    * Furthermore, the shouldPreBuffer decision is based upon the packet type,
    * and whether the returned value would fit in the current buffer without requiring a resize of the buffer.
    **/
    func optimalReadLengthWithDefault(defaultValue: Int, inout shouldPreBuffer : Bool) -> Int {
        var result = 0
        if readLength > 0 {
            // Read a specific length of data
            
            result = min(defaultValue, (readLength - bytesDone));
            
            // There is no need to prebuffer since we know exactly how much data we need to read.
            // Even if the buffer isn't currently big enough to fit this amount of data,
            // it would have to be resized eventually anyway.
            
            if shouldPreBuffer {
                shouldPreBuffer = false
            }
        } else {
            // Either reading until we find a specified terminator,
            // or we're simply reading all available data.
            //
            // In other words, one of:
            //
            // - readDataToData packet
            // - readDataWithTimeout packet
            
            if maxLength > 0 {
                result =  min(defaultValue, (maxLength - bytesDone));
            } else {
                result = defaultValue;
            }
            
            // Since we don't know the size of the read in advance,
            // the shouldPreBuffer decision is based upon whether the returned value would fit
            // in the current buffer without requiring a resize of the buffer.
            //
            // This is because, in all likelyhood, the amount read from the socket will be less than the default value.
            // Thus we should avoid over-allocating the read buffer when we can simply use the pre-buffer instead.
            
            if shouldPreBuffer {
                if let b = buffer {
                    let buffSize = b.length
                    let buffUsed = startOffset + bytesDone;
                    
                    let buffSpace = buffSize - buffUsed;
                    
                    if buffSpace >= result {
                        shouldPreBuffer = false
                    } else {
                        shouldPreBuffer = true
                    }
                }
            }
        }
        
        return result
    }
    
    /**
    * For read packets without a set terminator, returns the amount of data
    * that can be read without exceeding the readLength or maxLength.
    *
    * The given parameter indicates the number of bytes estimated to be available on the socket,
    * which is taken into consideration during the calculation.
    *
    * The given hint MUST be greater than zero.
    **/
    func readLengthForNonTermWithHint(bytesAvailable : Int) -> Int {
        assert(term == nil, "This method does not apply to term reads")
        assert(bytesAvailable > 0, "Invalid parameter: bytesAvailable")
        
        if (readLength > 0)
        {
            // Read a specific length of data
            
            return min(bytesAvailable, (readLength - bytesDone));
            
            // No need to avoid resizing the buffer.
            // If the user provided their own buffer,
            // and told us to read a certain length of data that exceeds the size of the buffer,
            // then it is clear that our code will resize the buffer during the read operation.
            //
            // This method does not actually do any resizing.
            // The resizing will happen elsewhere if needed.
        }
        else
        {
            // Read all available data
            
            var result = bytesAvailable;
            
            if (maxLength > 0)
            {
                result = min(result, (maxLength - bytesDone));
            }
            
            // No need to avoid resizing the buffer.
            // If the user provided their own buffer,
            // and told us to read all available data without giving us a maxLength,
            // then it is clear that our code might resize the buffer during the read operation.
            // 
            // This method does not actually do any resizing.
            // The resizing will happen elsewhere if needed.
            
            return result;
        }
    }
    
    
    /**
    * For read packets with a set terminator, returns the amount of data
    * that can be read without exceeding the maxLength.
    *
    * The given parameter indicates the number of bytes estimated to be available on the socket,
    * which is taken into consideration during the calculation.
    *
    * To optimize memory allocations, mem copies, and mem moves
    * the shouldPreBuffer boolean value will indicate if the data should be read into a prebuffer first,
    * or if the data can be read directly into the read packet's buffer.
    **/
    func readLengthForTermWithHint(bytesAvailable : Int, inout shouldPreBuffer : Bool) -> Int {
        assert(term != nil, "This method does not apply to non-term reads");
        assert(bytesAvailable > 0, "Invalid parameter: bytesAvailable");
        
        
        var result = bytesAvailable
        
        if (maxLength > 0)
        {
            result = min(result, (maxLength - bytesDone));
        }
        
        // Should the data be read into the read packet's buffer, or into a pre-buffer first?
        //
        // One would imagine the preferred option is the faster one.
        // So which one is faster?
        //
        // Reading directly into the packet's buffer requires:
        // 1. Possibly resizing packet buffer (malloc/realloc)
        // 2. Filling buffer (read)
        // 3. Searching for term (memcmp)
        // 4. Possibly copying overflow into prebuffer (malloc/realloc, memcpy)
        //
        // Reading into prebuffer first:
        // 1. Possibly resizing prebuffer (malloc/realloc)
        // 2. Filling buffer (read)
        // 3. Searching for term (memcmp)
        // 4. Copying underflow into packet buffer (malloc/realloc, memcpy)
        // 5. Removing underflow from prebuffer (memmove)
        //
        // Comparing the performance of the two we can see that reading
        // data into the prebuffer first is slower due to the extra memove.
        //
        // However:
        // The implementation of NSMutableData is open source via core foundation's CFMutableData.
        // Decreasing the length of a mutable data object doesn't cause a realloc.
        // In other words, the capacity of a mutable data object can grow, but doesn't shrink.
        //
        // This means the prebuffer will rarely need a realloc.
        // The packet buffer, on the other hand, may often need a realloc.
        // This is especially true if we are the buffer owner.
        // Furthermore, if we are constantly realloc'ing the packet buffer,
        // and then moving the overflow into the prebuffer,
        // then we're consistently over-allocating memory for each term read.
        // And now we get into a bit of a tradeoff between speed and memory utilization.
        //
        // The end result is that the two perform very similarly.
        // And we can answer the original question very simply by another means.
        //
        // If we can read all the data directly into the packet's buffer without resizing it first,
        // then we do so. Otherwise we use the prebuffer.
        
        if shouldPreBuffer, let b = buffer{
            let buffSize = b.length
            let buffUsed = startOffset + bytesDone;
            
            if (buffSize - buffUsed) >= result {
                shouldPreBuffer = false
            } else {
                shouldPreBuffer = true
            }
        }
        
        return result;

    }
    
    /**
    * For read packets with a set terminator,
    * returns the amount of data that can be read from the given preBuffer,
    * without going over a terminator or the maxLength.
    *
    * It is assumed the terminator has not already been read.
    **/
    
    func readLengthForTermWithPreBuffer(preBuffer : GCDAsyncSocketPreBuffer, inout found : Bool) -> Int {
        assert(term != nil, "This method does not apply to non-term reads");
        assert(preBuffer.availableBytes() > 0, "Invoked with empty pre buffer!");
        
        // We know that the terminator, as a whole, doesn't exist in our own buffer.
        // But it is possible that a _portion_ of it exists in our buffer.
        // So we're going to look for the terminator starting with a portion of our own buffer.
        //
        // Example:
        //
        // term length      = 3 bytes
        // bytesDone        = 5 bytes
        // preBuffer length = 5 bytes
        //
        // If we append the preBuffer to our buffer,
        // it would look like this:
        //
        // ---------------------
        // |B|B|B|B|B|P|P|P|P|P|
        // ---------------------
        //
        // So we start our search here:
        //
        // ---------------------
        // |B|B|B|B|B|P|P|P|P|P|
        // -------^-^-^---------
        //
        // And move forwards...
        //
        // ---------------------
        // |B|B|B|B|B|P|P|P|P|P|
        // ---------^-^-^-------
        //
        // Until we find the terminator or reach the end.
        //
        // ---------------------
        // |B|B|B|B|B|P|P|P|P|P|
        // ---------------^-^-^-
        
        found = false
        
        if term == nil || buffer == nil {
            return 0
        }
        let termLength = term!.length
        let preBufferLength = preBuffer.availableBytes();
        
        if (bytesDone + preBufferLength) < termLength{
            // Not enough data for a full term sequence yet
            return preBufferLength;
        }
        
        var maxPreBufferLength = 0
        if (maxLength > 0) {
            maxPreBufferLength = min(preBufferLength, (maxLength - bytesDone));
            
            // Note: maxLength >= termLength
        }
        else {
            maxPreBufferLength = preBufferLength;
        }
        
        let seq = UnsafeMutablePointer<CInt>.alloc(termLength)
        let termBuf = UnsafeMutablePointer<CInt>(term!.bytes)
        
        var bufLen = min(bytesDone, (termLength - 1));
        var buf = UnsafeMutablePointer<CInt>(buffer!.mutableBytes + startOffset + bytesDone - bufLen);
        
        var preLen = termLength - bufLen;
        var pre = preBuffer.readBuffer()
        
        let loopCount = bufLen + maxPreBufferLength - termLength + 1; // Plus one. See example above.
        
        var result = maxPreBufferLength;
        
        for _ in 0..<loopCount {
            
            if (bufLen > 0)
            {
                // Combining bytes from buffer and preBuffer
                seq.assignFrom(buf, count: bufLen)
                seq.advancedBy(bufLen).assignFrom(pre, count: preLen)
                if memcmp(seq, termBuf, termLength) == 0 {
                    result = preLen
                    found = true
                    break
                }
                
                buf += 1
                bufLen -= 1
                preLen += 1
            }
            else
            {
                // Comparing directly from preBuffer
                pre.assignFrom(termBuf, count: termLength)
                if memcmp(pre, termBuf, termLength) == 0 {
                    let preOffset = pre - preBuffer.readBuffer(); // pointer arithmetic
                    
                    result = preOffset + termLength;
                    found = true
                    break
                }
                
                pre += 1
            }
        }
        
        // There is no need to avoid resizing the buffer in this particular situation.
        return result
    }
    
    /**
    * For read packets with a set terminator, scans the packet buffer for the term.
    * It is assumed the terminator had not been fully read prior to the new bytes.
    *
    * If the term is found, the number of excess bytes after the term are returned.
    * If the term is not found, this method will return -1.
    *
    * Note: A return value of zero means the term was found at the very end.
    *
    * Prerequisites:
    * The given number of bytes have been added to the end of our buffer.
    * Our bytesDone variable has NOT been changed due to the prebuffered bytes.
    **/
    func searchForTermAfterPreBuffering(numberOfBytes numBytes : ssize_t) -> Int {
        assert(term != nil, "This method does not apply to non-term reads");
        
        // The implementation of this method is very similar to the above method.
        // See the above method for a discussion of the algorithm used here.
        if buffer == nil {
            return -1
        }
        
        let buff = buffer!.mutableBytes
        let buffLength = bytesDone + numBytes
        
        let termBuff = UnsafeMutablePointer<CInt>(term!.bytes)
        let termLength = term!.length
        
        // Note: We are dealing with unsigned integers,
        // so make sure the math doesn't go below zero.
        
        var i = ((buffLength - numBytes) >= termLength) ? (buffLength - numBytes - termLength + 1) : 0
        
        while (i + termLength <= buffLength)
        {
            let subBuffer = UnsafeMutablePointer<CInt>( buff + startOffset + i )
            
            if memcmp(subBuffer, termBuff, termLength) == 0 {
                return buffLength - (i + termLength)
            }
            
            i += 1
        }
        
        return -1
    }
}

