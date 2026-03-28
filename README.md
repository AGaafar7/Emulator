# Emulator: 16-bit Emulator & Integrated IDE

**Emulator** is a high-performance 8086/8088 CPU emulator and development environment built entirely in Swift and SwiftUI for macOS. It features a custom-built two-pass assembler, a memory-mapped VGA display, and a real-time instruction execution engine.


<img width="1372" height="651" alt="Screenshot 2026-03-28 at 2 45 30 AM" src="https://github.com/user-attachments/assets/893430e7-f79c-4361-ab19-70d84f693914" />

# 🚀 Features

### 🧠 CPU Core
- **Full 16-bit Architecture:** Implementation of the Intel 8086 instruction set.
- **Register Suite:** Accurate simulation of General Purpose (AX, BX, CX, DX), Index (SI, DI), Pointer (SP, BP), and Segment (CS, DS, SS, ES) registers.
- **Flag Logic:** Full support for Zero (ZF), Sign (SF), Carry (CF), Overflow (OF), and Auxiliary Carry (AF) flags.
- **Interrupt System:** Simulated BIOS (INT 10h, INT 16h) and DOS (INT 21h) API services.

### 🛠 Integrated Two-Pass Assembler
- **Syntax Highlighting:** Real-time code coloring for mnemonics, registers, and constants.
- **Label Support:** Sophisticated label resolution for loops (`LOOP`) and jumps (`JMP`, `JE`, `JNZ`, etc.).
- **Memory Variables:** Support for data definition directives (`DB`, `DW`) and bracket-based memory addressing (`MOV AX, [VAR]`).
- **Procedure Logic:** Functional `CALL` and `RET` mechanisms with stack management.

### 🖥 Virtual Hardware
- **VGA Text Mode:** Real-time rendering of the `0xB800:0000` memory segment (80x25 characters).
- **Color Attributes:** Support for 16-color foregrounds and backgrounds via the VGA attribute byte.
- **Interactive Keyboard:** BIOS-level keyboard buffer allowing user input to interact with running programs.
- **Mode 13h Ready:** Foundation for 320x200 256-color graphics.

## 🛠 Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/AGaafar7/Emulator.git
   ```
2. Open `Emulator.xcodeproj` in Xcode 15+.
3. Select **My Mac** as the run destination.
4. Press `Cmd + R` to build and run.

## 📝 Usage Example: The "Typewriter" Program

Paste the following code into the built-in editor to test the keyboard and VGA synchronization:

```assembly
; --- Setup Segments ---
MOV AX, CS
MOV DS, AX
MOV AX, 0B800H
MOV ES, AX
MOV DI, 0

; --- Main Interactive Loop ---
GET_KEY:
    MOV AH, 00H      ; BIOS wait for key
    INT 16H          ; Result returns in AL
    
    MOV AH, 0Eh      ; Yellow color attribute
    STOSW            ; Draw character and move cursor
    
    CMP AL, 13       ; Check if 'Enter' was pressed
    JE FINISH
    
    JMP GET_KEY

FINISH:
    HLT
```

## 🏗 Project Structure

- **`CPU8086.swift`**: The heart of the emulator. Contains the Fetch-Decode-Execute cycle and opcode switch.
- **`Assembler8086.swift`**: Logic for converting assembly text into machine code (Pass 1: Labels, Pass 2: Encoding).
- **`VGAView.swift`**: Optimized SwiftUI/Canvas view that renders the virtual memory segment as a visual screen.
- **`Registers.swift`**: Data structures for the 8086 register file and flag bit-masking.

## 🚧 Roadmap
- [ ] Implement full Mode 13h (320x200) Pixel Rendering.
- [ ] Add Hex Memory Viewer.
- [ ] Expand INT 21h for File System I/O.
- [ ] Step-by-Step Debugger with live register highlighting.

## 🤝 Contributing
Contributions are welcome! If you have optimized an opcode or added a new BIOS interrupt, feel free to open a Pull Request.

---
**Created by [Ahmed Gaafar](https://github.com/AGaafar7)**  
*Project started on March 27, 2026.*
