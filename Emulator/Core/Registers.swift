//
//  Registers.swift
//  Emulator
//
//  Created by Ahmed Gaafar on 27/03/2026.
//


import Foundation

struct Registers {
    var ax: UInt16 = 0
    var bx: UInt16 = 0
    var cx: UInt16 = 0
    var dx: UInt16 = 0
    
    var sp: UInt16 = 0xFFFE
    var bp: UInt16 = 0
    var si: UInt16 = 0
    var di: UInt16 = 0
    
    var cs: UInt16 = 0xFFFF
    var ds: UInt16 = 0
    var ss: UInt16 = 0
    var es: UInt16 = 0
    
    var ip: UInt16 = 0x0000
    var flags: UInt16 = 0
    
    // x86 standard mapping for 16-bit registers:
    // 0:AX, 1:CX, 2:DX, 3:BX, 4:SP, 5:BP, 6:SI, 7:DI
    mutating func setReg16(index: UInt8, value: UInt16) {
        switch index {
        case 0: ax = value; case 1: cx = value; case 2: dx = value; case 3: bx = value
        case 4: sp = value; case 5: bp = value; case 6: si = value; case 7: di = value
        default: break
        }
    }
    
    func getReg16(index: UInt8) -> UInt16 {
        switch index {
        case 0: return ax; case 1: return cx; case 2: return dx; case 3: return bx
        case 4: return sp; case 5: return bp; case 6: return si; case 7: return di
        default: return 0
        }
    }
    
    // 0:AL, 1:CL, 2:DL, 3:BL, 4:AH, 5:CH, 6:DH, 7:BH
    mutating func setReg8(index: UInt8, value: UInt8) {
        let val16 = UInt16(value)
        switch index {
            case 0: ax = (ax & 0xFF00) | val16         // AL
            case 1: cx = (cx & 0xFF00) | val16         // CL
            case 2: dx = (dx & 0xFF00) | val16         // DL
            case 3: bx = (bx & 0xFF00) | val16         // BL
            case 4: ax = (ax & 0x00FF) | (val16 << 8)  // AH
            case 5: cx = (cx & 0x00FF) | (val16 << 8)  // CH
            case 6: dx = (dx & 0x00FF) | (val16 << 8)  // DH
            case 7: bx = (bx & 0x00FF) | (val16 << 8)  // BH
            default: break
        }
    }
        
    func getReg8(index: UInt8) -> UInt8 {
        switch index {
            case 0: return UInt8(ax & 0x00FF)         // AL
            case 1: return UInt8(cx & 0x00FF)         // CL
            case 2: return UInt8(dx & 0x00FF)         // DL
            case 3: return UInt8(bx & 0x00FF)         // BL
            case 4: return UInt8((ax & 0xFF00) >> 8)  // AH
            case 5: return UInt8((cx & 0xFF00) >> 8)  // CH
            case 6: return UInt8((dx & 0xFF00) >> 8)  // DH
            case 7: return UInt8((bx & 0xFF00) >> 8)  // BH
            default: return 0
        }
    }
    
        // Carry Flag (Bit 0) - Set if math overflows the bit width
        var cf: Bool {
            get { (flags & 0x0001) != 0 }
            set { if newValue { flags |= 0x0001 } else { flags &= ~0x0001 } }
        }
        // Zero Flag (Bit 6) - Set if math result is exactly zero
        var zf: Bool {
            get { (flags & 0x0040) != 0 }
            set { if newValue { flags |= 0x0040 } else { flags &= ~0x0040 } }
        }
        // Sign Flag (Bit 7) - Set if the highest bit of the result is 1 (negative)
        var sf: Bool {
            get { (flags & 0x0080) != 0 }
            set { if newValue { flags |= 0x0080 } else { flags &= ~0x0080 } }
        }
        // Overflow Flag (Bit 11) - Set if signed math overflows
        var of: Bool {
            get { (flags & 0x0800) != 0 }
            set { if newValue { flags |= 0x0800 } else { flags &= ~0x0800 } }
        }
    var df: Bool { // Direction Flag (Bit 10)
        get { (flags & 0x0400) != 0 }
        set { if newValue { flags |= 0x0400 } else { flags &= ~0x0400 } }
    }
    // In struct Registers
    var af: Bool {
        get { (flags & 0x0010) != 0 }
        set { if newValue { flags |= 0x0010 } else { flags &= ~0x0010 } }
    }
}
