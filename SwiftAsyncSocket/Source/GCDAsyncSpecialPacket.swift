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

class GCDAsyncSpecialPacket {
    var tlsSettings : [String:AnyObject] = [:]
    
    init(){
        
    }
    
    convenience init(withTLSSettings tls : [String:AnyObject]){
        self.init()
        self.tlsSettings = tls
    }
}