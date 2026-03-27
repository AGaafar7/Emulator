//
//  EmulatorViewModel.swift
//  Emulator
//
//  Created by Ahmed Gaafar on 27/03/2026.
//


import SwiftUI
import Combine

class EmulatorViewModel: ObservableObject {
    @Published var cpu = CPU8086()
    @Published var displayOutput: String = "Emu8086 System Ready.\n"
    @Published var assemblyCode: String = """
    MOV AX, 0B800H
    MOV ES, AX
    MOV DI, 0
    MOV CX, 2000
    MOV AL, 2EH
    REP STOSB
    HLT
    """
    @Published var errorLog: String = ""
    private let assembler = Assembler8086()

    func assembleAndLoad() {
        do {
            let binary = try assembler.assemble(code: assemblyCode)
            cpu.reset() // ONLY reset when loading new code
            cpu.loadProgram(binary: binary)
            errorLog = "Assemble Successful."
        } catch {
            errorLog = error.localizedDescription
        }
    }

    private var runTimer: Timer?
    
    init() {
           cpu.onPrint = { [weak self] text in
               DispatchQueue.main.async {
                   self?.displayOutput += text
               }
           }
       }
    
    func loadTortureTest() {
        cpu.reset()
        displayOutput = "System Reset.\n"
        
        // We explicitly set DS = CS (0x0700) at the start of the program
        let program: [UInt8] = [
            0x8C, 0xC8,             // 0100: MOV AX, CS
            0x8E, 0xD8,             // 0102: MOV DS, AX (Now DS is 0700h)
            0xB8, 0x00, 0xB8,       // 0104: MOV AX, B800h
            0x8E, 0xC0,             // 0107: MOV ES, AX
            
            0x31, 0xFF,             // 0109: XOR DI, DI
            0xB9, 0xD0, 0x07,       // 010B: MOV CX, 2000 (Full screen)
            0xB0, 0x2E,             // 010E: MOV AL, '.'
            0xF3, 0xAA,             // 0110: REP STOSB
            
            0xBA, 0x1B, 0x01,       // 0112: MOV DX, 011Bh (Offset to string below)
            0xB4, 0x09,             // 0115: MOV AH, 09h
            0xCD, 0x21,             // 0117: INT 21h
            0xCD, 0x20,             // 0119: INT 20h
            
            // Data exactly at 011Bh
            0x0A, 0x0D, 0x56, 0x47, 0x41, 0x20, 0x4F, 0x4B, 0x21, 0x24 // "\r\nVGA OK!$"
        ]
        
        cpu.loadProgram(binary: program)
        displayOutput += "Loading Torture Test (Internal DS Setup)...\n"
        objectWillChange.send()
    }
    func loadDummyProgram() {
        cpu.reset()
        
        // Program logic:
        // 1. Setup ES to point to VGA Memory (B800h)
        // 2. Use REP STOSB to fill the screen with characters
        // 3. Perform BCD Math (9 + 2 = 11 decimal)
        // 4. Print "SYSTEM OK$" using DOS INT 21h
        
        let program: [UInt8] = [
            // --- 1. Setup Video Memory ---
            0xB8, 0x00, 0xB8,       // MOV AX, B800h
            0x8E, 0xC0,             // MOV ES, AX (Tests Segment Move)
            
            // --- 2. Clear Screen with Blue Dots ---
            0x31, 0xFF,             // XOR DI, DI (DI = 0)
            0xB9, 0xD0, 0x07,       // MOV CX, 2000 (80x25 characters)
            0xB0, 0xFA,             // MOV AL, 0xFA (Middle dot character '·')
            0xF3, 0xAA,             // REP STOSB (Tests REP prefix + STOSB + B800 mapping)
            
            // --- 3. Draw "!" at top left ---
            0x26, 0xC6, 0x05, 0x21, // MOV BYTE PTR ES:[DI], '!' (Tests Segment Override)
            
            // --- 4. BCD Math Test (9 + 2) ---
            0xB0, 0x09,             // MOV AL, 9
            0x04, 0x02,             // ADD AL, 2  (AL is now 0Bh)
            0x37,                   // AAA        (AL becomes 01h, AH becomes 01h)
            
            // --- 5. DOS Success Message ---
            0xBA, 0x1A, 0x01,       // MOV DX, 011Ah (Offset to string below)
            0xB4, 0x09,             // MOV AH, 09h
            0xCD, 0x21,             // INT 21h (Print String)
            
            0xCD, 0x20,             // INT 20h (Terminate)
            
            // Data Section (at offset 011Ah)
            0x0A, 0x0D, 0x53, 0x59, 0x53, 0x54, 0x45, 0x4D, 0x20, 0x4F, 0x4B, 0x24 // "\nSYSTEM OK$"
        ]
        
        cpu.loadProgram(binary: program)
        displayOutput += "Loaded Complex Torture Test...\n"
        objectWillChange.send()
    }
    func stepCPU() {
        cpu.step()
        objectWillChange.send() // Force UI update
    }
    
    func runCPU() {
        if cpu.isRunning { return }
        cpu.isRunning = true
        
        runTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            guard let self = self, self.cpu.isRunning else {
                self?.runTimer?.invalidate()
                return
            }
            
            // Run a small batch for responsiveness
            for _ in 0..<15 {
                if self.cpu.isRunning {
                    self.cpu.step()
                }
            }
            // Force the screen to update
            self.objectWillChange.send()
        }
    }
    func stopCPU() {
        cpu.isRunning = false
        runTimer?.invalidate()
        objectWillChange.send()
    }
    
    func resetCPU() {
        stopCPU()
        cpu.reset()
        displayOutput = "System Reset.\n"
        objectWillChange.send()
    }
}
