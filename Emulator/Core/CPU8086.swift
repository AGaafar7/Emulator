//
//  CPU8086.swift
//  Emulator
//
//  Created by Ahmed Gaafar on 27/03/2026.
//


import Foundation

class CPU8086 {
    var registers = Registers()
    var memory = [UInt8](repeating: 0, count: 1024 * 1024) // 1MB Memory for 8086
    var isRunning = false
    private var repeatPrefix: Bool = false
    private var segmentOverride: UInt16? = nil
    var keyBuffer: [UInt8] = []
    var waitingForKey = false
    var onPrint: ((String) -> Void)?
    
    func reset() {
        registers = Registers()
        // BIOS starts at FFFF:0000 traditionally, but for simple EMU, we start at 0100 (COM file format)
        registers.cs = 0x0700
        registers.ip = 0x0100
        memory = [UInt8](repeating: 0, count: 1024 * 1024)
    }
    
    func loadProgram(binary: [UInt8], atSegment segment: UInt16 = 0x0700, offset: UInt16 = 0x0100) {
        let physicalAddress = Int(segment) * 16 + Int(offset)
        for (index, byte) in binary.enumerated() {
            if physicalAddress + index < memory.count {
                memory[physicalAddress + index] = byte
            }
        }
    }
    
    // Add these helper methods inside CPU8086
    private func fetchByte() -> UInt8 {
        let physicalIp = Int(registers.cs) * 16 + Int(registers.ip)
        guard physicalIp < memory.count else { return 0 }
        let byte = memory[physicalIp]
        registers.ip &+= 1
        return byte
    }
    // Add this helper method right under fetchByte()
    private func fetchWord() -> UInt16 {
        let lowByte = fetchByte()
        let highByte = fetchByte()
        return UInt16(lowByte) | (UInt16(highByte) << 8)
    }
    
    // --- MEMORY ACCESS HELPERS ---
    private func readMemoryByte(segment: UInt16, offset: UInt16) -> UInt8 {
            let physicalAddress = Int(segment) * 16 + Int(offset)
            return physicalAddress < memory.count ? memory[physicalAddress] : 0
        }
        
        private func writeMemoryWord(segment: UInt16, offset: UInt16, value: UInt16) {
            let physicalAddress = Int(segment) * 16 + Int(offset)
            if physicalAddress + 1 < memory.count {
                memory[physicalAddress] = UInt8(value & 0xFF)             // Low byte
                memory[physicalAddress + 1] = UInt8((value >> 8) & 0xFF)  // High byte
            }
        }

        private func readMemoryWord(segment: UInt16, offset: UInt16) -> UInt16 {
            let physicalAddress = Int(segment) * 16 + Int(offset)
            if physicalAddress + 1 < memory.count {
                let lo = UInt16(memory[physicalAddress])
                let hi = UInt16(memory[physicalAddress + 1])
                return lo | (hi << 8)
            }
            return 0
        }
    
    //Handle interrupt
    private func handleInterrupt(_ intNum: UInt8) {
        switch intNum {
            
        // --- BIOS VIDEO SERVICES ---
        case 0x10:
            let ah = registers.getReg8(index: 4)
            switch ah {
            case 0x0E: // Teletype Output (Print char in AL)
                let char = String(format: "%c", registers.getReg8(index: 0))
                onPrint?(char)
            case 0x02: // Set Cursor Position (DH=Row, DL=Col)
                // Logic for visual cursor can be added here
                break
            case 0x00: // Set Video Mode (AL=Mode)
                onPrint?("[Video Mode Set to \(registers.getReg8(index: 0))h]\n")
            default:
                print("BIOS Video INT 10h AH=\(String(format:"%02X", ah)) not implemented.")
            }

        // --- BIOS KEYBOARD SERVICES ---
            // 2. Update the INT 16h case inside handleInterrupt
        case 0x16:
            let ah = registers.getReg8(index: 4) // AH
            if ah == 0x00 { // Wait for key
                if keyBuffer.isEmpty {
                    // Stay exactly on this INT 16h instruction
                    registers.ip &-= 2
                    return
                }
                // A key finally arrived!
                let key = keyBuffer.removeFirst()
                registers.setReg8(index: 0, value: key) // Put key in AL
            }
            
        // --- DOS TERMINATE (The old way) ---
        case 0x20:
            isRunning = false
            onPrint?("\nProgram Terminated (INT 20h).")

        // --- DOS API SERVICES ---
        case 0x21:
            let ah = registers.getReg8(index: 4)
            switch ah {
                
            case 0x01: // Read Character with Echo
                registers.setReg8(index: 0, value: 0x0D) // Return Carriage Return for now
                
            case 0x02: // Character Output (DL)
                let char = String(format: "%c", registers.getReg8(index: 2))
                onPrint?(char)
                
            case 0x09: // String Output (DS:DX ending in '$')
                var offset = registers.dx
                var b = readMemoryByte(segment: registers.ds, offset: offset)
                var str = ""
                while b != 0x24 { // '$'
                    str.append(Character(UnicodeScalar(b)))
                    offset &+= 1
                    b = readMemoryByte(segment: registers.ds, offset: offset)
                }
                onPrint?(str)
                
            
                
            case 0x2A: // Get System Date
                registers.cx = 2026 // Year
                registers.setReg8(index: 6, value: 3)  // DH = Month (March)
                registers.setReg8(index: 2, value: 27) // DL = Day
                
            case 0x2C: // Get System Time
                registers.setReg8(index: 4, value: 4)  // CH = Hour
                registers.setReg8(index: 5, value: 30) // CL = Minute
                
            case 0x30: // Get DOS Version
                registers.setReg8(index: 0, value: 5) // AL = Major version (DOS 5.0)
                registers.setReg8(index: 4, value: 0) // AH = Minor version
                
            case 0x4C: // Terminate with Return Code (AL)
                let code = registers.getReg8(index: 0)
                onPrint?("\nProgram Terminated with exit code \(code).")
                isRunning = false
                
            default:
                print("DOS API INT 21h AH=\(String(format:"%02X", ah)) not implemented.")
            }

        default:
            print("Unimplemented Interrupt: 0x\(String(format:"%02X", intNum))")
        }
    }
    
    // --- STACK HELPERS ---
        
        private func push16(_ value: UInt16) {
            // The stack grows DOWN in memory, so we subtract 2 bytes first
            registers.sp &-= 2
            writeMemoryWord(segment: registers.ss, offset: registers.sp, value: value)
        }
        
        private func pop16() -> UInt16 {
            // Read the value at the current Stack Pointer, then move the pointer UP by 2 bytes
            let value = readMemoryWord(segment: registers.ss, offset: registers.sp)
            registers.sp &+= 2
            return value
        }
        
        // Decodes the ModR/M byte to find the exact memory address
        private func getEffectiveAddress(modrm: ModRM) -> (segment: UInt16, offset: UInt16) {
            var offset: UInt16 = 0
            var segment: UInt16 = segmentOverride ?? registers.ds // Use override if present

            // 1. Calculate base offset from RM bits
            switch modrm.rm {
                   case 0: offset = registers.bx &+ registers.si
                   case 1: offset = registers.bx &+ registers.di
                   case 2: offset = registers.bp &+ registers.si; if segmentOverride == nil { segment = registers.ss }
                   case 3: offset = registers.bp &+ registers.di; if segmentOverride == nil { segment = registers.ss }
                   case 4: offset = registers.si
                   case 5: offset = registers.di
                   case 6:
                       if modrm.mod == 0 { offset = fetchWord() }
                       else { offset = registers.bp; if segmentOverride == nil { segment = registers.ss } }
                   case 7: offset = registers.bx
                   default: break
               }
            
            // 2. Add displacement based on MOD bits
            if modrm.mod == 1 {
                // 8-bit signed displacement (e.g., [BX + 5])
                let disp8 = Int8(bitPattern: fetchByte())
                offset = UInt16(bitPattern: Int16(disp8) &+ Int16(bitPattern: offset))
            } else if modrm.mod == 2 {
                // 16-bit displacement (e.g., [BX + 0x1000])
                let disp16 = fetchWord()
                offset = offset &+ disp16
            }
            
            return (segment, offset)
        }
    
    //cmp
    private func cmp16(dest: UInt16, src: UInt16) {
        // Perform subtraction but don't store the result
        _ = sub16(dest: dest, src: src)
    }

    private func cmp8(dest: UInt8, src: UInt8) {
        let result8 = dest &- src
        
        registers.cf = dest < src
        registers.zf = result8 == 0
        registers.sf = (result8 & 0x80) != 0
        
        let signDest = (dest & 0x80) != 0
        let signSrc = (src & 0x80) != 0
        let signRes = (result8 & 0x80) != 0
        // Signed overflow: (pos - neg = neg) OR (neg - pos = pos)
        registers.of = (signDest != signSrc) && (signDest != signRes)
    }
    
    //jmp
    private func jumpRelative8(_ offset: Int8) {
        let currentIP = Int16(bitPattern: registers.ip)
        registers.ip = UInt16(bitPattern: currentIP &+ Int16(offset))
    }
    
    //flag
    private func updateFlagsLogical(_ result: UInt16) {
        registers.zf = (result == 0)
        registers.sf = (result & 0x8000) != 0
        registers.cf = false
        registers.of = false
    }
    
    func step() {
        if waitingForKey {
            if !keyBuffer.isEmpty {
                waitingForKey = false // Key arrived! Resume.
            } else {
                return // Still no key, do nothing this step.
            }
        }
        
        segmentOverride = nil
        repeatPrefix = false
        let startIP = registers.ip // Save the exact start
        
        var opcode = fetchByte()
        
        // Prefix loop (Supports multiple prefixes like REP ES:)
        var isPrefix = true
        while isPrefix {
            if opcode == 0xF3 { repeatPrefix = true; opcode = fetchByte() }
            else if opcode == 0x26 { segmentOverride = registers.es; opcode = fetchByte() }
            else if opcode == 0x2E { segmentOverride = registers.cs; opcode = fetchByte() }
            else if opcode == 0x36 { segmentOverride = registers.ss; opcode = fetchByte() }
            else if opcode == 0x3E { segmentOverride = registers.ds; opcode = fetchByte() }
            else { isPrefix = false }
        }
        
        if opcode == 0x00 { isRunning = false; return }
        
        execute(opcode: opcode)
        
        // --- UPDATED REP LOGIC ---
        // We added 0xA5 (MOVSW) and 0xAB (STOSW) to this list
        let isStringOp = (opcode == 0xA4 || opcode == 0xA5 || opcode == 0xAA || opcode == 0xAB || opcode == 0xA6 || opcode == 0xAE)
        
        if repeatPrefix && isStringOp {
            if registers.cx > 0 {
                registers.cx &-= 1 // Decrement count
                
                if registers.cx > 0 {
                    // If we are using CMPS (A6) or SCAS (AE), we must also check the Zero Flag
                    let isCompare = (opcode == 0xA6 || opcode == 0xAE)
                    if isCompare && !registers.zf {
                        repeatPrefix = false
                    } else {
                        // Jump back to the START of the instruction (including prefixes)
                        registers.ip = startIP
                    }
                }
            }
        }
    }
    private func execute(opcode: UInt8) {
        switch opcode {
            
        case 0x09: // OR r/m16, r16
            let modrm = ModRM(fetchByte())
            let src = registers.getReg16(index: modrm.reg)
            if modrm.mod == 3 {
                let dest = registers.getReg16(index: modrm.rm)
                let res = dest | src
                registers.setReg16(index: modrm.rm, value: res)
                updateFlagsLogical(res)
            }

        case 0x06: // PUSH ES
            push16(registers.es)

        case 0x07: // POP ES
            registers.es = pop16()
            
        // --- ARITHMETIC (ADD / ADC / SUB / SBB) ---
        case 0x01: // ADD r/m16, r16
            let modrm = ModRM(fetchByte())
            let src = registers.getReg16(index: modrm.reg)
            if modrm.mod == 3 {
                let dest = registers.getReg16(index: modrm.rm)
                registers.setReg16(index: modrm.rm, value: add16(dest: dest, src: src))
            }

        case 0x29: // SUB r/m16, r16
            let modrm = ModRM(fetchByte())
            let src = registers.getReg16(index: modrm.reg)
            if modrm.mod == 3 {
                let dest = registers.getReg16(index: modrm.rm)
                registers.setReg16(index: modrm.rm, value: sub16(dest: dest, src: src))
            }
        case 0x03: // ADD r16, r/m16
            let modrm = ModRM(fetchByte())
            let destValue = registers.getReg16(index: modrm.reg)
            let ea = getEffectiveAddress(modrm: modrm)
            let srcValue = (modrm.mod == 3) ? registers.getReg16(index: modrm.rm) : readMemoryWord(segment: ea.segment, offset: ea.offset)
            registers.setReg16(index: modrm.reg, value: add16(dest: destValue, src: srcValue))
            
        case 0x04: // ADD AL, imm8
            registers.setReg8(index: 0, value: add8(dest: registers.getReg8(index: 0), src: fetchByte()))

        case 0x05: // ADD AX, imm16
            registers.ax = add16(dest: registers.ax, src: fetchWord())

        case 0x11: // ADC r/m16, r16
            let modrm = ModRM(fetchByte())
            let src = registers.getReg16(index: modrm.reg)
            let ea = getEffectiveAddress(modrm: modrm)
            let dest = (modrm.mod == 3) ? registers.getReg16(index: modrm.rm) : readMemoryWord(segment: ea.segment, offset: ea.offset)
            let res = adc16(dest: dest, src: src)
            if modrm.mod == 3 { registers.setReg16(index: modrm.rm, value: res) }
            else { writeMemoryWord(segment: ea.segment, offset: ea.offset, value: res) }

        case 0x13: // ADC r16, r/m16
            let modrm = ModRM(fetchByte())
            let dest = registers.getReg16(index: modrm.reg)
            let ea = getEffectiveAddress(modrm: modrm)
            let src = (modrm.mod == 3) ? registers.getReg16(index: modrm.rm) : readMemoryWord(segment: ea.segment, offset: ea.offset)
            registers.setReg16(index: modrm.reg, value: adc16(dest: dest, src: src))

        case 0x2B: // SUB r16, r/m16
            let modrm = ModRM(fetchByte())
            let destValue = registers.getReg16(index: modrm.reg)
            let ea = getEffectiveAddress(modrm: modrm)
            let srcValue = (modrm.mod == 3) ? registers.getReg16(index: modrm.rm) : readMemoryWord(segment: ea.segment, offset: ea.offset)
            registers.setReg16(index: modrm.reg, value: sub16(dest: destValue, src: srcValue))

        case 0x2C: // SUB AL, imm8
            registers.setReg8(index: 0, value: sub8(dest: registers.getReg8(index: 0), src: fetchByte()))

        case 0x2D: // SUB AX, imm16
            registers.ax = sub16(dest: registers.ax, src: fetchWord())

        case 0x19: // SBB r/m16, r16
            let modrm = ModRM(fetchByte())
            let src = registers.getReg16(index: modrm.reg)
            let ea = getEffectiveAddress(modrm: modrm)
            let dest = (modrm.mod == 3) ? registers.getReg16(index: modrm.rm) : readMemoryWord(segment: ea.segment, offset: ea.offset)
            let res = sbb16(dest: dest, src: src)
            if modrm.mod == 3 { registers.setReg16(index: modrm.rm, value: res) }
            else { writeMemoryWord(segment: ea.segment, offset: ea.offset, value: res) }

        case 0x1B: // SBB r16, r/m16
            let modrm = ModRM(fetchByte())
            let dest = registers.getReg16(index: modrm.reg)
            let ea = getEffectiveAddress(modrm: modrm)
            let src = (modrm.mod == 3) ? registers.getReg16(index: modrm.rm) : readMemoryWord(segment: ea.segment, offset: ea.offset)
            registers.setReg16(index: modrm.reg, value: sbb16(dest: dest, src: src))

        // --- LOGIC (AND / OR / XOR / TEST) ---
        case 0x08: // OR r/m8, r8
            let modrm = ModRM(fetchByte())
            let src = registers.getReg8(index: modrm.reg)
            let ea = getEffectiveAddress(modrm: modrm)
            let dest = (modrm.mod == 3) ? registers.getReg8(index: modrm.rm) : readMemoryByte(segment: ea.segment, offset: ea.offset)
            let res = dest | src
            if modrm.mod == 3 { registers.setReg8(index: modrm.rm, value: res) }
            else { writeMemoryByte(segment: ea.segment, offset: ea.offset, value: res) }
            updateFlagsLogical(UInt16(res))

        case 0x0B: // OR r16, r/m16
            let modrm = ModRM(fetchByte())
            let dest = registers.getReg16(index: modrm.reg)
            let ea = getEffectiveAddress(modrm: modrm)
            let src = (modrm.mod == 3) ? registers.getReg16(index: modrm.rm) : readMemoryWord(segment: ea.segment, offset: ea.offset)
            let res = dest | src
            registers.setReg16(index: modrm.reg, value: res)
            updateFlagsLogical(res)

        case 0x0C: // OR AL, imm8
            let res = registers.getReg8(index: 0) | fetchByte()
            registers.setReg8(index: 0, value: res)
            updateFlagsLogical(UInt16(res))

        case 0x20: // AND r/m8, r8
            let modrm = ModRM(fetchByte())
            let src = registers.getReg8(index: modrm.reg)
            let ea = getEffectiveAddress(modrm: modrm)
            let dest = (modrm.mod == 3) ? registers.getReg8(index: modrm.rm) : readMemoryByte(segment: ea.segment, offset: ea.offset)
            let res = dest & src
            if modrm.mod == 3 { registers.setReg8(index: modrm.rm, value: res) }
            else { writeMemoryByte(segment: ea.segment, offset: ea.offset, value: res) }
            updateFlagsLogical(UInt16(res))

        case 0x21: // AND r/m16, r16
            let modrm = ModRM(fetchByte())
            let src = registers.getReg16(index: modrm.reg)
            let ea = getEffectiveAddress(modrm: modrm)
            let dest = (modrm.mod == 3) ? registers.getReg16(index: modrm.rm) : readMemoryWord(segment: ea.segment, offset: ea.offset)
            let res = dest & src
            if modrm.mod == 3 { registers.setReg16(index: modrm.rm, value: res) }
            else { writeMemoryWord(segment: ea.segment, offset: ea.offset, value: res) }
            updateFlagsLogical(res)

        case 0x24: // AND AL, imm8
            let res = registers.getReg8(index: 0) & fetchByte()
            registers.setReg8(index: 0, value: res)
            updateFlagsLogical(UInt16(res))

        case 0x30: // XOR r/m8, r8
            let modrm = ModRM(fetchByte())
            let src = registers.getReg8(index: modrm.reg)
            let ea = getEffectiveAddress(modrm: modrm)
            let dest = (modrm.mod == 3) ? registers.getReg8(index: modrm.rm) : readMemoryByte(segment: ea.segment, offset: ea.offset)
            let res = dest ^ src
            if modrm.mod == 3 { registers.setReg8(index: modrm.rm, value: res) }
            else { writeMemoryByte(segment: ea.segment, offset: ea.offset, value: res) }
            updateFlagsLogical(UInt16(res))

        case 0x31: // XOR r/m16, r16
            let modrm = ModRM(fetchByte())
            let src = registers.getReg16(index: modrm.reg)
            let ea = getEffectiveAddress(modrm: modrm)
            let dest = (modrm.mod == 3) ? registers.getReg16(index: modrm.rm) : readMemoryWord(segment: ea.segment, offset: ea.offset)
            let res = dest ^ src
            if modrm.mod == 3 { registers.setReg16(index: modrm.rm, value: res) }
            else { writeMemoryWord(segment: ea.segment, offset: ea.offset, value: res) }
            updateFlagsLogical(res)

        case 0x85: // TEST r/m16, r16
            let modrm = ModRM(fetchByte())
            let v1 = registers.getReg16(index: modrm.reg)
            let ea = getEffectiveAddress(modrm: modrm)
            let v2 = (modrm.mod == 3) ? registers.getReg16(index: modrm.rm) : readMemoryWord(segment: ea.segment, offset: ea.offset)
            updateFlagsLogical(v1 & v2)

        // --- COMPARES ---
        case 0x39: // CMP r/m16, r16
            let modrm = ModRM(fetchByte())
            let src = registers.getReg16(index: modrm.reg)
            let ea = getEffectiveAddress(modrm: modrm)
            let dest = (modrm.mod == 3) ? registers.getReg16(index: modrm.rm) : readMemoryWord(segment: ea.segment, offset: ea.offset)
            cmp16(dest: dest, src: src)

        case 0x3B: // CMP r16, r/m16
            let modrm = ModRM(fetchByte())
            let dest = registers.getReg16(index: modrm.reg)
            let ea = getEffectiveAddress(modrm: modrm)
            let src = (modrm.mod == 3) ? registers.getReg16(index: modrm.rm) : readMemoryWord(segment: ea.segment, offset: ea.offset)
            cmp16(dest: dest, src: src)

        // --- DATA MOVEMENT (MOV / LEA / XCHG) ---
        case 0x8C: // MOV r/m16, Sreg (Move Segment Register to Register or Memory)
            let modrm = ModRM(fetchByte())
            let sregValue: UInt16
            
            // Determine which segment register to read (0:ES, 1:CS, 2:SS, 3:DS)
            switch modrm.reg {
            case 0: sregValue = registers.es
            case 1: sregValue = registers.cs
            case 2: sregValue = registers.ss
            case 3: sregValue = registers.ds
            default: sregValue = 0
            }

            if modrm.mod == 3 {
                // Move to register (e.g., MOV AX, CS)
                registers.setReg16(index: modrm.rm, value: sregValue)
            } else {
                // Move to memory (e.g., MOV [BX], DS)
                let ea = getEffectiveAddress(modrm: modrm)
                writeMemoryWord(segment: ea.segment, offset: ea.offset, value: sregValue)
            }
        case 0x88: // MOV r/m8, r8
            let modrm = ModRM(fetchByte())
            let val = registers.getReg8(index: modrm.reg)
            if modrm.mod == 3 { registers.setReg8(index: modrm.rm, value: val) }
            else { let ea = getEffectiveAddress(modrm: modrm); writeMemoryByte(segment: ea.segment, offset: ea.offset, value: val) }

        case 0x89: // MOV r/m16, r16
            let modrm = ModRM(fetchByte())
            let val = registers.getReg16(index: modrm.reg)
            if modrm.mod == 3 { registers.setReg16(index: modrm.rm, value: val) }
            else { let ea = getEffectiveAddress(modrm: modrm); writeMemoryWord(segment: ea.segment, offset: ea.offset, value: val) }

        case 0x8A: // MOV r8, r/m8
            let modrm = ModRM(fetchByte())
            let val: UInt8 = (modrm.mod == 3) ? registers.getReg8(index: modrm.rm) : readMemoryByte(segment: getEffectiveAddress(modrm: modrm).segment, offset: getEffectiveAddress(modrm: modrm).offset)
            registers.setReg8(index: modrm.reg, value: val)

        case 0x8B: // MOV r16, r/m16
            let modrm = ModRM(fetchByte())
            let val: UInt16 = (modrm.mod == 3) ? registers.getReg16(index: modrm.rm) : readMemoryWord(segment: getEffectiveAddress(modrm: modrm).segment, offset: getEffectiveAddress(modrm: modrm).offset)
            registers.setReg16(index: modrm.reg, value: val)

        case 0x8D: // LEA r16, mem
            let modrm = ModRM(fetchByte())
            registers.setReg16(index: modrm.reg, value: getEffectiveAddress(modrm: modrm).offset)

        case 0x8E: // MOV Sreg, r/m16
            let modrm = ModRM(fetchByte())
            let val = (modrm.mod == 3) ? registers.getReg16(index: modrm.rm) : readMemoryWord(segment: registers.ds, offset: getEffectiveAddress(modrm: modrm).offset)
            switch modrm.reg { case 0: registers.es = val; case 1: registers.cs = val; case 2: registers.ss = val; case 3: registers.ds = val; default: break }

        case 0x86: // XCHG r/m8, r8
            let modrm = ModRM(fetchByte())
            let r1 = registers.getReg8(index: modrm.reg)
            let ea = getEffectiveAddress(modrm: modrm)
            let r2 = (modrm.mod == 3) ? registers.getReg8(index: modrm.rm) : readMemoryByte(segment: ea.segment, offset: ea.offset)
            registers.setReg8(index: modrm.reg, value: r2)
            if modrm.mod == 3 { registers.setReg8(index: modrm.rm, value: r1) }
            else { writeMemoryByte(segment: ea.segment, offset: ea.offset, value: r1) }

        case 0x91...0x97: // XCHG AX, reg16
            let regIdx = opcode - 0x90
            let temp = registers.ax
            registers.ax = registers.getReg16(index: regIdx)
            registers.setReg16(index: regIdx, value: temp)

        case 0xA0: // MOV AL, [offset]
            registers.setReg8(index: 0, value: readMemoryByte(segment: registers.ds, offset: fetchWord()))
        case 0xA1: // MOV AX, [offset]
            registers.ax = readMemoryWord(segment: registers.ds, offset: fetchWord())
        case 0xA2: // MOV [offset], AL
            writeMemoryByte(segment: registers.ds, offset: fetchWord(), value: registers.getReg8(index: 0))
        case 0xA3: // MOV [offset], AX
            writeMemoryWord(segment: registers.ds, offset: fetchWord(), value: registers.ax)

        case 0xB0...0xB7: // MOV reg8, imm8
            registers.setReg8(index: opcode - 0xB0, value: fetchByte())
        case 0xB8...0xBF: // MOV reg16, imm16
            registers.setReg16(index: opcode - 0xB8, value: fetchWord())
            
        //BCD Adjust Instructions
        case 0x27: // DAA (Decimal Adjust AL after Addition)
            var al = registers.getReg8(index: 0)
            let oldAL = al
            let oldCF = registers.cf
            if (al & 0x0F) > 9 || registers.af {
                al = al &+ 6
                registers.cf = oldCF || (al < oldAL)
                registers.af = true
            } else { registers.af = false }
            if oldAL > 0x99 || oldCF {
                al = al &+ 0x60
                registers.cf = true
            } else { registers.cf = false }
            registers.setReg8(index: 0, value: al)
            updateFlagsLogical(UInt16(al)) // Updates ZF, SF

        case 0x2F: // DAS (Decimal Adjust AL after Subtraction)
            var al = registers.getReg8(index: 0)
            let oldAL = al
            let oldCF = registers.cf
            if (al & 0x0F) > 9 || registers.af {
                al = al &- 6
                registers.cf = oldCF || (oldAL < 6)
                registers.af = true
            } else { registers.af = false }
            if oldAL > 0x99 || oldCF {
                al = al &- 0x60
                registers.cf = true
            }
            registers.setReg8(index: 0, value: al)
            updateFlagsLogical(UInt16(al))

        case 0x37: // AAA (ASCII Adjust AL after Addition)
            if (registers.getReg8(index: 0) & 0x0F) > 9 || registers.af {
                registers.setReg8(index: 0, value: (registers.getReg8(index: 0) &+ 6) & 0x0F)
                registers.setReg8(index: 4, value: registers.getReg8(index: 4) &+ 1) // INC AH
                registers.af = true; registers.cf = true
            } else { registers.af = false; registers.cf = false; registers.setReg8(index: 0, value: registers.getReg8(index: 0) & 0x0F) }

        case 0x3F: // AAS (ASCII Adjust AL after Subtraction)
            if (registers.getReg8(index: 0) & 0x0F) > 9 || registers.af {
                registers.setReg8(index: 0, value: (registers.getReg8(index: 0) &- 6) & 0x0F)
                registers.setReg8(index: 4, value: registers.getReg8(index: 4) &- 1) // DEC AH
                registers.af = true; registers.cf = true
            } else { registers.af = false; registers.cf = false; registers.setReg8(index: 0, value: registers.getReg8(index: 0) & 0x0F) }

        case 0xD4: // AAM (ASCII Adjust for Multiply)
            let base = fetchByte() // Standard is 10
            let al = registers.getReg8(index: 0)
            registers.setReg8(index: 4, value: al / base) // AH
            registers.setReg8(index: 0, value: al % base) // AL
            updateFlagsLogical(UInt16(registers.ax))

        case 0xD5: // AAD (ASCII Adjust before Division)
            let base = fetchByte() // Standard is 10
            let ah = registers.getReg8(index: 4)
            let al = registers.getReg8(index: 0)
            registers.setReg8(index: 0, value: (ah &* base) &+ al)
            registers.setReg8(index: 4, value: 0)
            updateFlagsLogical(UInt16(registers.ax))

        // --- INC / DEC ---
            
        case 0x40...0x47: // INC r16
            let idx = opcode - 0x40
            registers.setReg16(index: idx, value: add16(dest: registers.getReg16(index: idx), src: 1))
        case 0x48...0x4F: // DEC r16
            let idx = opcode - 0x48
            registers.setReg16(index: idx, value: sub16(dest: registers.getReg16(index: idx), src: 1))

        // --- STACK (PUSH / POP) ---
        case 0x50...0x57: push16(registers.getReg16(index: opcode - 0x50))
        case 0x58...0x5F: registers.setReg16(index: opcode - 0x58, value: pop16())
        case 0x9C: push16(registers.flags)
        case 0x9D: registers.flags = pop16()

        // --- CONVERSIONS (CBW / CWD) ---
        case 0x98: // CBW
            let al = registers.getReg8(index: 0)
            registers.ax = (al & 0x80 != 0) ? (0xFF00 | UInt16(al)) : UInt16(al)
        case 0x99: // CWD
            registers.dx = (registers.ax & 0x8000 != 0) ? 0xFFFF : 0x0000

        // --- STRING OPS ---
            
        case 0xAB: // STOSW (Store AX at ES:DI)
            writeMemoryWord(segment: registers.es, offset: registers.di, value: registers.ax)
            // Ensure this line exists! It moves the cursor to the next spot
            registers.di = registers.df ? registers.di &- 2 : registers.di &+ 2

        case 0xA5: // MOVSW (Move word from DS:SI to ES:DI)
            writeMemoryWord(segment: registers.es, offset: registers.di, value: readMemoryWord(segment: registers.ds, offset: registers.si))
            // Both pointers move by 2
            registers.si = registers.df ? registers.si &- 2 : registers.si &+ 2
            registers.di = registers.df ? registers.di &- 2 : registers.di &+ 2
            
        case 0xA4: // MOVSB
            
            writeMemoryByte(segment: registers.es, offset: registers.di, value: readMemoryByte(segment: registers.ds, offset: registers.si))
            registers.si = registers.df ? registers.si &- 1 : registers.si &+ 1
            registers.di = registers.df ? registers.di &- 1 : registers.di &+ 1
        case 0xAA: // STOSB
            writeMemoryByte(segment: registers.es, offset: registers.di, value: registers.getReg8(index: 0))
            registers.di = registers.df ? registers.di &- 1 : registers.di &+ 1
        case 0xA6: // CMPSB
            let b1 = readMemoryByte(segment: registers.ds, offset: registers.si)
            let b2 = readMemoryByte(segment: registers.es, offset: registers.di)
            _ = sub8(dest: b1, src: b2)
            registers.si = registers.df ? registers.si &- 1 : registers.si &+ 1
            registers.di = registers.df ? registers.di &- 1 : registers.di &+ 1
        case 0xAE: // SCASB
            let target = readMemoryByte(segment: registers.es, offset: registers.di)
            _ = sub8(dest: registers.getReg8(index: 0), src: target)
            registers.di = registers.df ? registers.di &- 1 : registers.di &+ 1

        // --- JUMPS / CALLS ---
        case 0x74: let off = Int8(bitPattern: fetchByte()); if registers.zf { jumpRelative8(off) }
        case 0x75: let off = Int8(bitPattern: fetchByte()); if !registers.zf { jumpRelative8(off) }
        case 0x7C: let off = Int8(bitPattern: fetchByte()); if registers.sf != registers.of { jumpRelative8(off) }
        case 0x7D: let off = Int8(bitPattern: fetchByte()); if registers.sf == registers.of { jumpRelative8(off) }
        case 0x7E: let off = Int8(bitPattern: fetchByte()); if registers.zf || (registers.sf != registers.of) { jumpRelative8(off) }
        case 0x7F: let off = Int8(bitPattern: fetchByte()); if !registers.zf && (registers.sf == registers.of) { jumpRelative8(off) }
        case 0xEB: jumpRelative8(Int8(bitPattern: fetchByte()))
        case 0xE2: let off = Int8(bitPattern: fetchByte()); registers.cx &-= 1; if registers.cx != 0 { jumpRelative8(off) }
        case 0xE3: let off = Int8(bitPattern: fetchByte()); if registers.cx == 0 { jumpRelative8(off) }
        case 0xE8: let off = Int16(bitPattern: fetchWord()); push16(registers.ip); registers.ip = UInt16(bitPattern: Int16(bitPattern: registers.ip) &+ off)
        case 0xC3: registers.ip = pop16()
            
        //Advanced Pointer Loading
        case 0xC4: // LES r16, m16:32
            let modrm = ModRM(fetchByte())
            let ea = getEffectiveAddress(modrm: modrm)
            registers.setReg16(index: modrm.reg, value: readMemoryWord(segment: ea.segment, offset: ea.offset))
            registers.es = readMemoryWord(segment: ea.segment, offset: ea.offset + 2)

        case 0xC5: // LDS r16, m16:32
            let modrm = ModRM(fetchByte())
            let ea = getEffectiveAddress(modrm: modrm)
            registers.setReg16(index: modrm.reg, value: readMemoryWord(segment: ea.segment, offset: ea.offset))
            registers.ds = readMemoryWord(segment: ea.segment, offset: ea.offset + 2)

        // --- SYSTEM / FLAG / IO ---
        case 0x90: break // NOP
        case 0xCD: handleInterrupt(fetchByte())
        case 0xF4: isRunning = false // HLT
        case 0xF5: registers.cf = !registers.cf // CMC
        case 0xF8: registers.cf = false // CLC
        case 0xF9: registers.cf = true // STC
        case 0xFC: registers.df = false // CLD
        case 0xFD: registers.df = true // STD
        case 0x9E: registers.flags = (registers.flags & 0xFF00) | UInt16(registers.getReg8(index: 4)) // SAHF
        case 0x9F: registers.setReg8(index: 4, value: UInt8(registers.flags & 0xFF)) // LAHF
        case 0xE4...0xE7, 0xEE: _ = fetchByte(); // Minimal IO
            
        // --- GROUP 1 (80, 81, 83) ---
        case 0x80, 0x81, 0x83:
            let modrm = ModRM(fetchByte())
            let imm: UInt16 = (opcode == 0x81) ? fetchWord() : UInt16(bitPattern: Int16(Int8(bitPattern: fetchByte())))
            let ea = getEffectiveAddress(modrm: modrm)
            var dest = (modrm.mod == 3) ? registers.getReg16(index: modrm.rm) : readMemoryWord(segment: ea.segment, offset: ea.offset)
            
            if opcode == 0x80 { // 8-bit version
                let imm8 = UInt8(imm & 0xFF)
                var dest8 = (modrm.mod == 3) ? registers.getReg8(index: modrm.rm) : readMemoryByte(segment: ea.segment, offset: ea.offset)
                switch modrm.reg {
                case 0: dest8 = add8(dest: dest8, src: imm8); case 1: dest8 |= imm8; updateFlagsLogical(UInt16(dest8))
                case 2: dest8 = adc8(dest: dest8, src: imm8); case 3: dest8 = sbb8(dest: dest8, src: imm8)
                case 4: dest8 &= imm8; updateFlagsLogical(UInt16(dest8)); case 5: dest8 = sub8(dest: dest8, src: imm8)
                case 6: dest8 ^= imm8; updateFlagsLogical(UInt16(dest8)); case 7: _ = sub8(dest: dest8, src: imm8); return
                default: return
                }
                if modrm.mod == 3 { registers.setReg8(index: modrm.rm, value: dest8) }
                else { writeMemoryByte(segment: ea.segment, offset: ea.offset, value: dest8) }
            } else { // 16-bit version
                switch modrm.reg {
                case 0: dest = add16(dest: dest, src: imm); case 1: dest |= imm; updateFlagsLogical(dest)
                case 2: dest = adc16(dest: dest, src: imm); case 3: dest = sbb16(dest: dest, src: imm)
                case 4: dest &= imm; updateFlagsLogical(dest); case 5: dest = sub16(dest: dest, src: imm)
                case 6: dest ^= imm; updateFlagsLogical(dest); case 7: _ = sub16(dest: dest, src: imm); return
                default: return
                }
                if modrm.mod == 3 { registers.setReg16(index: modrm.rm, value: dest) }
                else { writeMemoryWord(segment: ea.segment, offset: ea.offset, value: dest) }
            }

        // --- GROUP 3 (F6, F7) ---
        case 0xF6, 0xF7:
            let modrm = ModRM(fetchByte())
            let ea = getEffectiveAddress(modrm: modrm)
            if opcode == 0xF6 { // 8-bit
                let val = (modrm.mod == 3) ? registers.getReg8(index: modrm.rm) : readMemoryByte(segment: ea.segment, offset: ea.offset)
                switch modrm.reg {
                case 0, 1: updateFlagsLogical(UInt16(val & fetchByte())) // TEST
                case 2: let r = ~val; if modrm.mod == 3 { registers.setReg8(index: modrm.rm, value: r) } else { writeMemoryByte(segment: ea.segment, offset: ea.offset, value: r) }
                case 3: let r = sub8(dest: 0, src: val); if modrm.mod == 3 { registers.setReg8(index: modrm.rm, value: r) } else { writeMemoryByte(segment: ea.segment, offset: ea.offset, value: r) }
                case 4: registers.ax = UInt16(registers.getReg8(index: 0)) * UInt16(val); registers.cf = (registers.ax > 0xFF); registers.of = registers.cf
                case 6: if val != 0 { registers.setReg8(index: 0, value: UInt8(registers.ax / UInt16(val))); registers.setReg8(index: 4, value: UInt8(registers.ax % UInt16(val))) } else { isRunning = false }
                default: break
                }
            } else { // 16-bit
                let val = (modrm.mod == 3) ? registers.getReg16(index: modrm.rm) : readMemoryWord(segment: ea.segment, offset: ea.offset)
                switch modrm.reg {
                case 0, 1: updateFlagsLogical(val & fetchWord()) // TEST
                case 2: let r = ~val; if modrm.mod == 3 { registers.setReg16(index: modrm.rm, value: r) } else { writeMemoryWord(segment: ea.segment, offset: ea.offset, value: r) }
                case 3: let r = sub16(dest: 0, src: val); if modrm.mod == 3 { registers.setReg16(index: modrm.rm, value: r) } else { writeMemoryWord(segment: ea.segment, offset: ea.offset, value: r) }
                case 4: let r = UInt32(registers.ax) * UInt32(val); registers.ax = UInt16(r & 0xFFFF); registers.dx = UInt16(r >> 16); registers.cf = (registers.dx != 0); registers.of = registers.cf
                case 6: if val != 0 { let d = (UInt32(registers.dx) << 16) | UInt32(registers.ax); registers.ax = UInt16(d / UInt32(val)); registers.dx = UInt16(d % UInt32(val)) } else { isRunning = false }
                default: break
                }
            }

        case 0xFE: // Group 4 (8-bit INC/DEC)
            let modrm = ModRM(fetchByte())
            let ea = getEffectiveAddress(modrm: modrm)
            var val = (modrm.mod == 3) ? registers.getReg8(index: modrm.rm) : readMemoryByte(segment: ea.segment, offset: ea.offset)
            if modrm.reg == 0 { val = add8(dest: val, src: 1) } else if modrm.reg == 1 { val = sub8(dest: val, src: 1) }
            if modrm.mod == 3 { registers.setReg8(index: modrm.rm, value: val) } else { writeMemoryByte(segment: ea.segment, offset: ea.offset, value: val) }

        default:
            print("Unimplemented opcode: \(String(format:"%02X", opcode))")
            isRunning = false
        }
    }

    // Ensure you have this helper at the bottom of CPU8086:
    private func writeMemoryByte(segment: UInt16, offset: UInt16, value: UInt8) {
        let physicalAddress = Int(segment) * 16 + Int(offset)
        if physicalAddress < memory.count {
            memory[physicalAddress] = value
        }
    }
    //add helpers
    private func add16(dest: UInt16, src: UInt16) -> UInt16 {
            let result32 = UInt32(dest) + UInt32(src)
            let result16 = UInt16(result32 & 0xFFFF)
            
            registers.cf = result32 > 0xFFFF
            registers.zf = result16 == 0
            registers.sf = (result16 & 0x8000) != 0
            
            let signDest = (dest & 0x8000) != 0
            let signSrc = (src & 0x8000) != 0
            let signRes = (result16 & 0x8000) != 0
            // Overflow happens if two numbers with the same sign produce a result with a different sign
            registers.of = (signDest == signSrc) && (signDest != signRes)
            
            return result16
        }
    
    private func add8(dest: UInt8, src: UInt8) -> UInt8 {
        let res16 = UInt16(dest) + UInt16(src)
        let res8 = UInt8(res16 & 0xFF)
        
        registers.zf = (res8 == 0)
        registers.sf = (res8 & 0x80) != 0
        registers.cf = res16 > 0xFF
        
        // Overflow for 8-bit
        let sD = (dest & 0x80) != 0
        let sS = (src & 0x80) != 0
        let sR = (res8 & 0x80) != 0
        registers.of = (sD == sS) && (sD != sR)
        
        return res8
    }
    
    private func sub8(dest: UInt8, src: UInt8) -> UInt8 {
        let result8 = dest &- src
        
        registers.cf = dest < src
        registers.zf = result8 == 0
        registers.sf = (result8 & 0x80) != 0
        
        let signDest = (dest & 0x80) != 0
        let signSrc = (src & 0x80) != 0
        let signRes = (result8 & 0x80) != 0
        registers.of = (signDest != signSrc) && (signDest != signRes)
        
        return result8
    }
        
        private func sub16(dest: UInt16, src: UInt16) -> UInt16 {
            let result16 = dest &- src
            
            registers.cf = dest < src
            registers.zf = result16 == 0
            registers.sf = (result16 & 0x8000) != 0
            
            let signDest = (dest & 0x8000) != 0
            let signSrc = (src & 0x8000) != 0
            let signRes = (result16 & 0x8000) != 0
            // Overflow happens if subtracting a negative from a positive gives a negative, etc.
            registers.of = (signDest != signSrc) && (signDest != signRes)
            
            return result16
        }
    
    // --- ADC / SBB HELPERS ---

    private func adc16(dest: UInt16, src: UInt16) -> UInt16 {
        let carry: UInt32 = registers.cf ? 1 : 0
        let result32 = UInt32(dest) + UInt32(src) + carry
        let result16 = UInt16(result32 & 0xFFFF)
        
        registers.cf = result32 > 0xFFFF
        registers.zf = result16 == 0
        registers.sf = (result16 & 0x8000) != 0
        
        let signDest = (dest & 0x8000) != 0
        let signSrc = (src & 0x8000) != 0
        let signRes = (result16 & 0x8000) != 0
        // Overflow: adding two same-sign numbers results in a different sign
        registers.of = (signDest == signSrc) && (signDest != signRes)
        
        return result16
    }

    private func adc8(dest: UInt8, src: UInt8) -> UInt8 {
        let carry: UInt16 = registers.cf ? 1 : 0
        let result16 = UInt16(dest) + UInt16(src) + carry
        let result8 = UInt8(result16 & 0xFF)
        
        registers.cf = result16 > 0xFF
        registers.zf = result8 == 0
        registers.sf = (result8 & 0x80) != 0
        
        let signDest = (dest & 0x80) != 0
        let signSrc = (src & 0x80) != 0
        let signRes = (result8 & 0x80) != 0
        registers.of = (signDest == signSrc) && (signDest != signRes)
        
        return result8
    }

    private func sbb16(dest: UInt16, src: UInt16) -> UInt16 {
        let borrow: UInt32 = registers.cf ? 1 : 0
        let result32 = Int32(dest) - Int32(src) - Int32(borrow)
        let result16 = UInt16(bitPattern: Int16(truncatingIfNeeded: result32))
        
        registers.cf = result32 < 0
        registers.zf = result16 == 0
        registers.sf = (result16 & 0x8000) != 0
        
        let signDest = (dest & 0x8000) != 0
        let signSrc = (src & 0x8000) != 0
        let signRes = (result16 & 0x8000) != 0
        // Overflow: subtracting different signs results in a sign matching the subtrahend
        registers.of = (signDest != signSrc) && (signDest != signRes)
        
        return result16
    }

    private func sbb8(dest: UInt8, src: UInt8) -> UInt8 {
        let borrow: Int16 = registers.cf ? 1 : 0
        let result16 = Int16(dest) - Int16(src) - borrow
        let result8 = UInt8(bitPattern: Int8(truncatingIfNeeded: result16))
        
        registers.cf = result16 < 0
        registers.zf = result8 == 0
        registers.sf = (result8 & 0x80) != 0
        
        let signDest = (dest & 0x80) != 0
        let signSrc = (src & 0x80) != 0
        let signRes = (result8 & 0x80) != 0
        registers.of = (signDest != signSrc) && (signDest != signRes)
        
        return result8
    }
    
    func getScreenBuffer() -> [UInt8] {
        let start = 0xB800 * 16
        let length = 80 * 25 * 2
        // Ensure we don't go out of bounds of the 1MB memory
           if start + length <= memory.count {
               return Array(memory[start..<(start + length)])
           }
           return Array(repeating: 0, count: length)    }
}
