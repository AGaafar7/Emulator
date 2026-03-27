import SwiftUI
import Combine

struct VGAView: View {
    @EnvironmentObject var vm: EmulatorViewModel
    @FocusState private var isFocused: Bool
    
    let timer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()
    @State private var screenData: [UInt8] = Array(repeating: 0, count: 4000)
    
    var body: some View {
        Canvas { context, size in
            let charWidth = size.width / 80
            let charHeight = size.height / 25
            
            for row in 0..<25 {
                for col in 0..<80 {
                    let idx = (row * 80 + col) * 2
                    let charByte = screenData[idx]
                    let attrByte = screenData[idx + 1]
                    
                    let rect = CGRect(x: CGFloat(col) * charWidth, y: CGFloat(row) * charHeight, width: charWidth, height: charHeight)
                    
                    context.fill(Path(rect), with: .color(.black))
                    
                    let char = String(UnicodeScalar(charByte == 0 ? 32 : charByte))
                    var text = context.resolve(Text(char).font(.system(size: charHeight - 2, design: .monospaced)).bold())
                    text.shading = .color(colorFor(attribute: attrByte))
                    context.draw(text, in: rect)
                }
            }
        }
        // 1. Set the frame and background on the Canvas itself
        .frame(width: 640, height: 400)
        .background(Color.black)
        // 2. Keyboard focus modifiers
        .focusable()
        .focused($isFocused)
        .onAppear { isFocused = true }
        // 3. Update logic
        .onReceive(timer) { _ in
            self.screenData = vm.cpu.getScreenBuffer()
        }
        // 4. Click to focus helper
        .onTapGesture {
            isFocused = true
        }
        // 5. The hidden keyboard listener
        .background(
            KeyEventHandler { char in
                if isFocused {
                    vm.cpu.keyBuffer.append(char) // Add to queue
                }
            }
        )
    }

    private func colorFor(attribute: UInt8) -> Color {
        let foreground = attribute & 0x0F
        switch foreground {
        case 0x01: return .blue; case 0x02: return .green; case 0x04: return .red
        case 0x0E: return .yellow; case 0x0F: return .white; default: return .green
        }
    }
}

// Helper outside the main struct for cleaner code
struct KeyEventHandler: NSViewRepresentable {
    let onKeyDown: (UInt8) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Handle special keys
            var char: UInt8 = 0
            if event.keyCode == 36 { // Enter Key
                char = 13
            } else if let firstChar = event.characters?.first?.asciiValue {
                char = firstChar
            }
            
            if char != 0 {
                onKeyDown(char)
            }
            return event
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
