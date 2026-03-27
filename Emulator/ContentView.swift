//
//  ContentView.swift
//  Emulator
//
//  Created by Ahmed Gaafar on 27/03/2026.
//


import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: EmulatorViewModel
    
    var body: some View {
        HStack(spacing: 0) {
            // Left: Registers (already exists)
            VStack(alignment: .leading) {
                Text("Registers").font(.headline).padding(.bottom, 5)
                RegisterView(name: "AX", value: viewModel.cpu.registers.ax)
                RegisterView(name: "BX", value: viewModel.cpu.registers.bx)
                RegisterView(name: "CX", value: viewModel.cpu.registers.cx)
                RegisterView(name: "DX", value: viewModel.cpu.registers.dx)
                Divider()
                RegisterView(name: "CS", value: viewModel.cpu.registers.cs)
                RegisterView(name: "IP", value: viewModel.cpu.registers.ip)
                RegisterView(name: "SP", value: viewModel.cpu.registers.sp)
                Divider()
                Text("Flags").font(.headline).padding(.top, 5)
                HStack {
                    Text(viewModel.cpu.registers.zf ? "Z " : "- ")
                    Text(viewModel.cpu.registers.sf ? "S " : "- ")
                    Text(viewModel.cpu.registers.of ? "O " : "- ")
                    Text(viewModel.cpu.registers.cf ? "C " : "- ")
                }.monospaced().foregroundColor(.blue)
                Spacer()
            }
            .padding()
            .frame(width: 200)
            .background(Color(nsColor: .controlBackgroundColor))
            // Middle: Editor
            VStack {
                HStack {
                    Button("Assemble & Load") { viewModel.assembleAndLoad() }
                        .keyboardShortcut("b", modifiers: .command)
                    Button("Run") { viewModel.runCPU() }
                    Button("Stop") { viewModel.stopCPU() }
                }.padding()
                
                CodeEditor(text: $viewModel.assemblyCode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.1))
                
                Text(viewModel.errorLog)
                    .foregroundColor(.yellow)
                    .padding(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black)
            }
            .frame(width: 400)
            
            // Right: VGA Screen
            VStack {
                VGAView()
                    .frame(width: 640, height: 400)
                TextEditor(text: .constant(viewModel.displayOutput))
                    .frame(height: 100)
            }
        }
    }
}
struct RegisterView: View {
    let name: String
    let value: UInt16
    
    var body: some View {
        HStack {
            Text(name).bold()
            Spacer()
            Text(String(format: "0x%04X", value)).monospaced()
        }
    }
}


