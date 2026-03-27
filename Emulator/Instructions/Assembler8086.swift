import Foundation

class Assembler8086 {
    private let reg16Map = ["AX": 0, "CX": 1, "DX": 2, "BX": 3, "SP": 4, "BP": 5, "SI": 6, "DI": 7]
    private let reg8Map  = ["AL": 0, "CL": 1, "DL": 2, "BL": 3, "AH": 4, "CH": 5, "DH": 6, "BH": 7]
    private let sregMap  = ["ES": 0, "CS": 1, "SS": 2, "DS": 3]
    
    private var labels: [String: Int] = [:]
    private var currentAddress: Int = 0

    func assemble(code: String) throws -> [UInt8] {
        labels.removeAll()
        let lines = code.components(separatedBy: .newlines)
        
        // --- PASS 1: Calculate Label Positions ---
        currentAddress = 0x0100
        for line in lines {
            let codePart = line.components(separatedBy: ";").first ?? ""
            let clean = codePart.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty { continue }
            
            if clean.hasSuffix(":") {
                labels[clean.dropLast().trimmingCharacters(in: .whitespaces).uppercased()] = currentAddress
                continue
            }
            
            let parts = clean.uppercased().replacingOccurrences(of: ",", with: " ").components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            currentAddress += try estimateSize(parts: parts, originalLine: clean)
        }

        // --- PASS 2: Generate Machine Code ---
        var binary: [UInt8] = []
        currentAddress = 0x0100
        for (idx, line) in lines.enumerated() {
            let codePart = line.components(separatedBy: ";").first ?? ""
            let clean = codePart.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty || clean.hasSuffix(":") { continue }
            
            let parts = clean.uppercased().replacingOccurrences(of: ",", with: " ").components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            do {
                let bytes = try assembleLine(parts: parts, originalLine: clean)
                binary.append(contentsOf: bytes)
                currentAddress += bytes.count
            } catch {
                // Better Error Reporting
                let msg = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String ?? "Unknown error"
                throw NSError(domain: "Assembler", code: 1, userInfo: [NSLocalizedDescriptionKey: "Line \(idx + 1): \(msg)"])
            }
        }
        return binary
    }

    private func assembleLine(parts: [String], originalLine: String) throws -> [UInt8] {
        let mnemonic = parts[0].uppercased()
        switch mnemonic {
        case "MOV": return try handleMov(parts: parts)
        case "ADD", "SUB", "CMP", "AND", "OR", "XOR": return try handleArithmetic(mnemonic: mnemonic, parts: parts)
        case "INC", "DEC": return try handleIncDec(parts: parts)
        case "DB": return try handleDB(line: originalLine)
        case "DW": return parts.suffix(from: 1).flatMap { s in let v = parseImm16(s); return [UInt8(v & 0xFF), UInt8(v >> 8)] }
        case "JMP", "JE", "JZ", "JNE", "JNZ", "JL", "JG", "JB", "JA": return try handleJump(parts: parts)
        case "LOOP": return try handleJump(parts: parts, opcode: 0xE2)
        case "CALL": return try handleJump(parts: parts, opcode: 0xE8)
        case "RET": return [0xC3]
        case "INT": return [0xCD, parseImm8(parts[1])]
        case "HLT": return [0xF4]
        case "NOP": return [0x90]
        case "STOSB": return [0xAA]
        case "STOSW": return [0xAB]
        case "MOVSB": return [0xA4]
        case "MOVSW": return [0xA5]
        case "REP":
            var bytes: [UInt8] = [0xF3]
            if parts.count > 1 {
                let sub = parts[1].uppercased()
                if sub == "STOSB" { bytes.append(0xAA) }
                else if sub == "STOSW" { bytes.append(0xAB) }
                else if sub == "MOVSB" { bytes.append(0xA4) }
                else if sub == "MOVSW" { bytes.append(0xA5) }
            }
            return bytes
        default: throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unknown instruction: \(mnemonic)"])
        }
    }

    private func handleArithmetic(mnemonic: String, parts: [String]) throws -> [UInt8] {
        guard parts.count == 3 else { throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Math needs 2 args"]) }
        let dest = parts[1].uppercased()
        let src = parts[2].uppercased()
        let immSub = ["ADD": 0, "OR": 1, "AND": 4, "SUB": 5, "XOR": 6, "CMP": 7]
        
        // Reg16, Reg16
        if let dIdx = reg16Map[dest], let sIdx = reg16Map[src] {
            let regOps: [String: UInt8] = ["ADD": 0x01, "OR": 0x09, "AND": 0x21, "SUB": 0x29, "XOR": 0x31, "CMP": 0x39]
            return [regOps[mnemonic]!, UInt8(0xC0 | (sIdx << 3) | dIdx)]
        }
        // Reg16, Imm16
        if let dIdx = reg16Map[dest] {
            let val = parseImm16(src)
            if dest == "AX" { // Shortcut for AX
                let accOps: [String: UInt8] = ["ADD": 0x05, "OR": 0x0D, "AND": 0x25, "SUB": 0x2D, "XOR": 0x35, "CMP": 0x3D]
                return [accOps[mnemonic]!, UInt8(val & 0xFF), UInt8(val >> 8)]
            }
            return [0x81, UInt8(0xC0 | (immSub[mnemonic]! << 3) | dIdx), UInt8(val & 0xFF), UInt8(val >> 8)]
        }
        // Reg8, Imm8
        if let dIdx = reg8Map[dest] {
            let val = parseImm8(src)
            return [0x80, UInt8(0xC0 | (immSub[mnemonic]! << 3) | dIdx), val]
        }
        throw NSError(domain: "", code: 0)
    }

    private func handleJump(parts: [String], opcode: UInt8? = nil) throws -> [UInt8] {
        let targetLabel = parts[1].uppercased()
        guard let targetAddr = labels[targetLabel] else {
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Label '\(targetLabel)' missing"])
        }
        
        let jumpMap: [String: UInt8] = ["JMP": 0xEB, "JE": 0x74, "JZ": 0x74, "JNE": 0x75, "JNZ": 0x75, "JL": 0x7C, "JG": 0x7F, "JB": 0x72, "JA": 0x77, "CALL": 0xE8]
        let op = opcode ?? jumpMap[parts[0].uppercased()] ?? 0xEB
        
        if op == 0xE8 { // CALL (3 bytes)
            let distance = Int16(targetAddr - (currentAddress + 3))
            return [0xE8, UInt8(distance & 0xFF), UInt8((distance >> 8) & 0xFF)]
        } else { // Jumps (2 bytes)
            let distance = Int8(truncatingIfNeeded: targetAddr - (currentAddress + 2))
            return [op, UInt8(bitPattern: distance)]
        }
    }

    private func estimateSize(parts: [String], originalLine: String) throws -> Int {
        let m = parts[0].uppercased()
        let p1 = parts.count > 1 ? parts[1].uppercased() : ""
        let p2 = parts.count > 2 ? parts[2].uppercased() : ""

        switch m {
        case "MOV":
            if p1.hasPrefix("[") || p2.hasPrefix("[") { return 4 } // MOV AX, [VAR]
               if reg16Map[p1] != nil && reg16Map[p2] != nil { return 2 } // MOV AX, BX
               if sregMap[p1] != nil || sregMap[p2] != nil { return 2 } // MOV ES, AX
               if reg16Map[p1] != nil { return 3 } // MOV AX, 1234h
               if reg8Map[p1] != nil { return 2 } // MOV AL, 12h
               return 3
        case "ADD", "SUB", "CMP", "AND", "OR", "XOR":
            if p1 == "AX" && reg16Map[p2] == nil { return 3 } // Shortcut AX
            if reg8Map[p1] != nil && reg8Map[p2] == nil { return 3 } // Reg8, Imm8
            if reg16Map[p1] != nil && reg16Map[p2] != nil { return 2 } // Reg, Reg
            return 4 // Reg16, Imm16
        case "INC", "DEC": return reg16Map[p1] != nil ? 1 : 2
        case "CALL": return 3
        case "RET", "STOSB", "STOSW", "MOVSB", "MOVSW", "HLT", "NOP": return 1
        case "REP", "INT": return 2
        default: return 2 // Default for jumps/loops
        }
    }

    private func handleMov(parts: [String]) throws -> [UInt8] {
        let dest = parts[1].uppercased(); let src = parts[2].uppercased()
        if src.hasPrefix("[") && src.hasSuffix("]") {
            let name = src.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            if let addr = labels[name], let rIdx = reg16Map[dest] { return [0x8B, UInt8((rIdx << 3) | 0x06), UInt8(addr & 0xFF), UInt8(addr >> 8)] }
        }
        if let sIdx = sregMap[dest], let rIdx = reg16Map[src] { return [0x8E, UInt8(0xC0 | (sIdx << 3) | rIdx)] }
        if let rIdx = reg16Map[dest] {
            if let sIdx = sregMap[src] { return [0x8C, UInt8(0xC0 | (sIdx << 3) | rIdx)] }
            if let sIdx = reg16Map[src] { return [0x8B, UInt8(0xC0 | (rIdx << 3) | sIdx)] }
            let v = parseImm16(src); return [UInt8(0xB8 + rIdx), UInt8(v & 0xFF), UInt8(v >> 8)]
        }
        if let rIdx = reg8Map[dest] { return [UInt8(0xB0 + rIdx), parseImm8(src)] }
        return [0x90]
    }

    private func handleIncDec(parts: [String]) throws -> [UInt8] {
        let isInc = parts[0].uppercased() == "INC"
        let dest = parts[1].uppercased()
        if let rIdx = reg16Map[dest] { return [UInt8((isInc ? 0x40 : 0x48) + rIdx)] }
        if let rIdx = reg8Map[dest] { return [0xFE, UInt8(0xC0 | (isInc ? 0x00 : 0x08) | rIdx)] }
        return [0x90]
    }

    private func handleDB(line: String) throws -> [UInt8] {
        if let s = line.firstIndex(of: "'"), let e = line.lastIndex(of: "'"), s < e {
            return Array(line[line.index(after: s)..<e].utf8)
        }
        return line.uppercased().replacingOccurrences(of: ",", with: " ").components(separatedBy: .whitespaces).suffix(from: 1).map { parseImm8($0) }
    }

    private func parseImm8(_ s: String) -> UInt8 {
        let c = s.uppercased(); if let l = labels[c] { return UInt8(l & 0xFF) }
        if c.hasSuffix("H") { return UInt8(c.dropLast(), radix: 16) ?? 0 }
        return UInt8(c) ?? 0
    }

    private func parseImm16(_ s: String) -> UInt16 {
        let c = s.uppercased(); if let l = labels[c] { return UInt16(l) }
        if c.hasSuffix("H") { return UInt16(c.dropLast(), radix: 16) ?? 0 }
        return UInt16(c) ?? 0
    }
}
