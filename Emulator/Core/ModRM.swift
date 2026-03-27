//
//  ModRM.swift
//  Emulator
//
//  Created by Ahmed Gaafar on 27/03/2026.
//


import Foundation

struct ModRM {
    let mod: UInt8
    let reg: UInt8
    let rm: UInt8
    
    init(_ byte: UInt8) {
        self.mod = (byte >> 6) & 0x03
        self.reg = (byte >> 3) & 0x07
        self.rm  = byte & 0x07
    }
}