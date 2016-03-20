//
// Tom Sheffler
// Dec 2015
//

import Foundation
import Dispatch

#if os(Linux)
import Glibc
#else
import Darwin
#endif


print("Hello World!")

var someInts = [Int]()

print("someInts is of type [Int] with \(someInts.count) items.")

someInts = [1,2,3]

print("someInts is \(someInts) with \(someInts.count) items.")

let now = UInt64(DISPATCH_TIME_NOW)

print ("Now:\(now)")

 print ("Dispatch:\(dispatch_get_main_queue())")

let time = dispatch_time(now, Int64(0.5 * Double(NSEC_PER_SEC)))

print ("Time:\(time)")


var name = "com.example"
let queue = dispatch_queue_create(name.cStringUsingEncoding(NSUTF8StringEncoding)!, nil)

print("Main:\(queue.dynamicType)")

dispatch_after(time, queue, {
    print("Delayed!")
    print("name: \(dispatch_get_specific(&name).dynamicType)")
})

let s = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(0), 0, nil)

//Glibc.sleep(5)
