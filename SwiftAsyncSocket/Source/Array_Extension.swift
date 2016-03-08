//
//  Array_Extension.swift
//  SwiftAsyncSocket
//
//  Created by Joel Saltzman on 2/27/16.
//  Copyright © 2016 Joel Saltzman. All rights reserved.
//

import Foundation


extension Array where Element: Equatable {
    
    mutating func removeElement(element: Element) -> Element? {
        if let index = indexOf(element) {
            return removeAtIndex(index)
        }
        return nil
    }

}