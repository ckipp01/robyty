import AppKit
import SwiftUI

struct ItemText: NSViewRepresentable {
    var text: String
    var ink: NSColor
    var link: NSColor
    var done: Bool
    var onEdit: () -> Void

    final class Label: NSTextView {
        var onEdit: () -> Void = {}

        override func mouseDown(with event: NSEvent) {
            let local = convert(event.locationInWindow, from: nil)
            let idx = characterIndexForInsertion(at: local)
            let len = textStorage?.length ?? 0
            if len > 0 {
                let at = min(max(idx, 0), len - 1)
                if let url = link(at: at) {
                    NSWorkspace.shared.open(url)
                    return
                }
            }
            onEdit()
        }

        override var acceptsFirstResponder: Bool { false }

        private func link(at idx: Int) -> URL? {
            guard let storage = textStorage, idx < storage.length else { return nil }
            let value = storage.attribute(.link, at: idx, effectiveRange: nil)
            if let url = value as? URL { return url }
            if let s = value as? String { return URL(string: s) }
            return nil
        }
    }

    func makeNSView(context: Context) -> Label {
        let tv = Label()
        tv.isEditable = false
        tv.isSelectable = false
        tv.isRichText = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.lineBreakMode = .byWordWrapping
        tv.textContainer?.widthTracksTextView = true
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.textContainer?.containerSize = NSSize(width: 280, height: 10_000)
        apply(to: tv)
        tv.onEdit = onEdit
        return tv
    }

    func updateNSView(_ tv: Label, context: Context) {
        tv.onEdit = onEdit
        apply(to: tv)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Label, context: Context) -> CGSize? {
        let width = proposal.width ?? 280
        nsView.textContainer?.containerSize = NSSize(width: width, height: 10_000)
        nsView.frame.size.width = width
        if let container = nsView.textContainer {
            nsView.layoutManager?.ensureLayout(for: container)
            let used = nsView.layoutManager?.usedRect(for: container) ?? .zero
            return CGSize(width: width, height: max(16, ceil(used.height)))
        }
        return CGSize(width: width, height: 16)
    }

    private func apply(to tv: Label) {
        let font = NSFont.systemFont(ofSize: 13.5)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: ink,
            .paragraphStyle: para
        ]
        if done {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attrs[.strikethroughColor] = ink
        }
        let mutable = NSMutableAttributedString(string: text, attributes: attrs)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let ns = text as NSString
            detector.enumerateMatches(
                in: text,
                options: [],
                range: NSRange(location: 0, length: ns.length)
            ) { match, _, _ in
                guard let match, let url = match.url else { return }
                mutable.addAttributes([
                    .link: url,
                    .foregroundColor: link,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ], range: match.range)
            }
        }
        tv.textStorage?.setAttributedString(mutable)
        tv.linkTextAttributes = [
            .foregroundColor: link,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }
}

enum ItemInk {
    static let body = NSColor(srgbRed: 220 / 255, green: 215 / 255, blue: 186 / 255, alpha: 1)
    static let link = NSColor(srgbRed: 255 / 255, green: 160 / 255, blue: 102 / 255, alpha: 1)
    static let done = NSColor(srgbRed: 114 / 255, green: 113 / 255, blue: 105 / 255, alpha: 1)
    static let doneLink = NSColor(srgbRed: 255 / 255, green: 160 / 255, blue: 102 / 255, alpha: 0.4)
}
