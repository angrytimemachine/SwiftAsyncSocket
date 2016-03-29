//
//  sockaddr_un_extension.swift
//  SwiftAsyncSocket
//
//  Created by Joel Saltzman on 2/12/16.
//  Copyright © 2016 Joel Saltzman. All rights reserved.
//

import Foundation

extension sockaddr_un {
    
    /// Copies `path` into `sun_path`. Values located over the 104th index are
    /// not copied.
    mutating func setPath(path: UnsafePointer<Int8>, length: Int) {
        var array = [Int8](repeating: 0, count: 104)
        for i in 0..<length {
            array[i] = path[i]
        }
        setPath(array)
    }
    
    /// Copies a `path` into `sun_path`
    /// - Warning: Path must be at least 104 in length.
    mutating func setPath(path: [Int8]) {
        
        precondition(path.count >= 104, "Path must be at least 104 in length")
        
        sun_path.0 = path[0]
        // and so on for infinity ...
        // ... python is handy
        sun_path.1 = path[1]
        sun_path.2 = path[2]
        sun_path.3 = path[3]
        sun_path.4 = path[4]
        sun_path.5 = path[5]
        sun_path.6 = path[6]
        sun_path.7 = path[7]
        sun_path.8 = path[8]
        sun_path.9 = path[9]
        sun_path.10 = path[10]
        sun_path.11 = path[11]
        sun_path.12 = path[12]
        sun_path.13 = path[13]
        sun_path.14 = path[14]
        sun_path.15 = path[15]
        sun_path.16 = path[16]
        sun_path.17 = path[17]
        sun_path.18 = path[18]
        sun_path.19 = path[19]
        sun_path.20 = path[20]
        sun_path.21 = path[21]
        sun_path.22 = path[22]
        sun_path.23 = path[23]
        sun_path.24 = path[24]
        sun_path.25 = path[25]
        sun_path.26 = path[26]
        sun_path.27 = path[27]
        sun_path.28 = path[28]
        sun_path.29 = path[29]
        sun_path.30 = path[30]
        sun_path.31 = path[31]
        sun_path.32 = path[32]
        sun_path.33 = path[33]
        sun_path.34 = path[34]
        sun_path.35 = path[35]
        sun_path.36 = path[36]
        sun_path.37 = path[37]
        sun_path.38 = path[38]
        sun_path.39 = path[39]
        sun_path.40 = path[40]
        sun_path.41 = path[41]
        sun_path.42 = path[42]
        sun_path.43 = path[43]
        sun_path.44 = path[44]
        sun_path.45 = path[45]
        sun_path.46 = path[46]
        sun_path.47 = path[47]
        sun_path.48 = path[48]
        sun_path.49 = path[49]
        sun_path.50 = path[50]
        sun_path.51 = path[51]
        sun_path.52 = path[52]
        sun_path.53 = path[53]
        sun_path.54 = path[54]
        sun_path.55 = path[55]
        sun_path.56 = path[56]
        sun_path.57 = path[57]
        sun_path.58 = path[58]
        sun_path.59 = path[59]
        sun_path.60 = path[60]
        sun_path.61 = path[61]
        sun_path.62 = path[62]
        sun_path.63 = path[63]
        sun_path.64 = path[64]
        sun_path.65 = path[65]
        sun_path.66 = path[66]
        sun_path.67 = path[67]
        sun_path.68 = path[68]
        sun_path.69 = path[69]
        sun_path.70 = path[70]
        sun_path.71 = path[71]
        sun_path.72 = path[72]
        sun_path.73 = path[73]
        sun_path.74 = path[74]
        sun_path.75 = path[75]
        sun_path.76 = path[76]
        sun_path.77 = path[77]
        sun_path.78 = path[78]
        sun_path.79 = path[79]
        sun_path.80 = path[80]
        sun_path.81 = path[81]
        sun_path.82 = path[82]
        sun_path.83 = path[83]
        sun_path.84 = path[84]
        sun_path.85 = path[85]
        sun_path.86 = path[86]
        sun_path.87 = path[87]
        sun_path.88 = path[88]
        sun_path.89 = path[89]
        sun_path.90 = path[90]
        sun_path.91 = path[91]
        sun_path.92 = path[92]
        sun_path.93 = path[93]
        sun_path.94 = path[94]
        sun_path.95 = path[95]
        sun_path.96 = path[96]
        sun_path.97 = path[97]
        sun_path.98 = path[98]
        sun_path.99 = path[99]
        sun_path.100 = path[100]
        sun_path.101 = path[101]
        sun_path.102 = path[102]
        sun_path.103 = path[103]
//
    }
    // Retrieves `sun_path` into an arary.
    func getPath() -> [Int8] {
        var path = [Int8](repeating: 0, count: 104)
        
        path[0] = sun_path.0
        path[1] = sun_path.1
        path[2] = sun_path.2
        path[3] = sun_path.3
        path[4] = sun_path.4
        path[5] = sun_path.5
        path[6] = sun_path.6
        path[7] = sun_path.7
        path[8] = sun_path.8
        path[9] = sun_path.9
        path[10] = sun_path.10
        path[11] = sun_path.11
        path[12] = sun_path.12
        path[13] = sun_path.13
        path[14] = sun_path.14
        path[15] = sun_path.15
        path[16] = sun_path.16
        path[17] = sun_path.17
        path[18] = sun_path.18
        path[19] = sun_path.19
        path[20] = sun_path.20
        path[21] = sun_path.21
        path[22] = sun_path.22
        path[23] = sun_path.23
        path[24] = sun_path.24
        path[25] = sun_path.25
        path[26] = sun_path.26
        path[27] = sun_path.27
        path[28] = sun_path.28
        path[29] = sun_path.29
        path[30] = sun_path.30
        path[31] = sun_path.31
        path[32] = sun_path.32
        path[33] = sun_path.33
        path[34] = sun_path.34
        path[35] = sun_path.35
        path[36] = sun_path.36
        path[37] = sun_path.37
        path[38] = sun_path.38
        path[39] = sun_path.39
        path[40] = sun_path.40
        path[41] = sun_path.41
        path[42] = sun_path.42
        path[43] = sun_path.43
        path[44] = sun_path.44
        path[45] = sun_path.45
        path[46] = sun_path.46
        path[47] = sun_path.47
        path[48] = sun_path.48
        path[49] = sun_path.49
        path[50] = sun_path.50
        path[51] = sun_path.51
        path[52] = sun_path.52
        path[53] = sun_path.53
        path[54] = sun_path.54
        path[55] = sun_path.55
        path[56] = sun_path.56
        path[57] = sun_path.57
        path[58] = sun_path.58
        path[59] = sun_path.59
        path[60] = sun_path.60
        path[61] = sun_path.61
        path[62] = sun_path.62
        path[63] = sun_path.63
        path[64] = sun_path.64
        path[65] = sun_path.65
        path[66] = sun_path.66
        path[67] = sun_path.67
        path[68] = sun_path.68
        path[69] = sun_path.69
        path[70] = sun_path.70
        path[71] = sun_path.71
        path[72] = sun_path.72
        path[73] = sun_path.73
        path[74] = sun_path.74
        path[75] = sun_path.75
        path[76] = sun_path.76
        path[77] = sun_path.77
        path[78] = sun_path.78
        path[79] = sun_path.79
        path[80] = sun_path.80
        path[81] = sun_path.81
        path[82] = sun_path.82
        path[83] = sun_path.83
        path[84] = sun_path.84
        path[85] = sun_path.85
        path[86] = sun_path.86
        path[87] = sun_path.87
        path[88] = sun_path.88
        path[89] = sun_path.89
        path[90] = sun_path.90
        path[91] = sun_path.91
        path[92] = sun_path.92
        path[93] = sun_path.93
        path[94] = sun_path.94
        path[95] = sun_path.95
        path[96] = sun_path.96
        path[97] = sun_path.97
        path[98] = sun_path.98
        path[99] = sun_path.99
        path[100] = sun_path.100
        path[101] = sun_path.101
        path[102] = sun_path.102
        path[103] = sun_path.103
        
        return path
    }
}