//
//  CodeEditor.swift
//  Emulator
//
//  Created by Ahmed Gaafar on 27/03/2026.
//


import SwiftUI
import AppKit

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.backgroundColor = .clear
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
        highlight(textView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string
        }
    }
    
    // Simple color logic
    func highlight(_ textView: NSTextView) {
        let text = textView.string
        let range = NSRange(location: 0, length: text.utf16.count)
        textView.textStorage?.setAttributes([.foregroundColor: NSColor.white, .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)], range: range)
        
        let patterns: [String: NSColor] = [
            "\\b(MOV|INT|ADD|SUB|CMP|JE|JMP|RET|HLT|REP|STOSB|MOVSB)\\b": .systemPink, // Keywords
            "\\b(AX|BX|CX|DX|SI|DI|BP|SP|CS|DS|ES|SS|AL|AH|BL|BH|CL|CH|DL|DH)\\b": .systemCyan, // Registers
            ";.*": .systemGray, // Comments
            "\\b[0-9]+[H]?\\b": .systemYellow // Numbers
        ]
        
        for (pattern, color) in patterns {
            let regex = try! NSRegularExpression(pattern: pattern, options: [])
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                if let matchRange = match?.range {
                    textView.textStorage?.addAttribute(.foregroundColor, value: color, range: matchRange)
                }
            }
        }
    }
}