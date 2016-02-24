//
//  GCDAsyncSpecialPacket.swift
//  SwiftAsyncSocket
//
//  Created by Joel Saltzman on 1/10/16.
//  Copyright © 2016 Joel Saltzman. All rights reserved.
//

import Foundation

/**
 * The GCDAsyncSpecialPacket encompasses special instructions for interruptions in the read/write queues.
 * This class my be altered to support more than just TLS in the future.
 **/

class GCDAsyncSpecialPacket : GCDAsyncReadPacket {
    var tlsSettings : [String:AnyObject]
    
    init(withTLSSettings tls : [String:AnyObject]){
        tlsSettings = tls
        super.init(withData: nil, startOffset: 0, maxLength: 0, timeout: 0, readLength: 0, terminator: nil, tag: 0)
        
    }
}