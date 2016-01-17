//
//  Package.swift
//  SwiftAsyncSocket
//
//  Created by Joel Saltzman on 1/10/16.
//  Copyright © 2016 Joel Saltzman. All rights reserved.
//

import Foundation
#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif
