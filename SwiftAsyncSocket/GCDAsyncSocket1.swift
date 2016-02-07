//
//  GCDAsyncSocket.swift
//  SwiftAsyncSocket
//
//  Created by Joel Saltzman on 2/6/16.
//  Copyright © 2016 Joel Saltzman. All rights reserved.
//

import Foundation

class GCDAsyncSocket {
    func run() {
        let socketFD:Int32 = 1
        close(socketFD)
        
        var interface6 = NSMutableData.init()
        var addr6 : sockaddr_in6 = UnsafePointer<sockaddr_in6>(interface6.mutableBytes).memory
//        addr6.sin6_port = htons(self.localPort4());//CFSwapInt32HostToBig
        
        if fcntl(socketFD, F_SETFL, O_NONBLOCK) == -1 {
            close(socketFD)
        }

    }
}