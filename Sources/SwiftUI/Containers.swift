// Render nodes for scrolling, lists, navigation, text input and toggles.

extension Color {
    static let groupedBackground = Color(242, 242, 247)    // iOS systemGroupedBackground
    static let separator = Color(198, 198, 200)
    static let rowHighlight = Color(209, 209, 214)
    static let placeholder = Color(196, 196, 199)
    static let switchOff = Color(233, 233, 234)
}

// MARK: - Per-render identity and persistent UI state

extension Runtime {
    static var scrollOffsets: [Int: Double] = [:]
    static var scrollCounter = 0
    static var fieldCounter = 0
    static var focusedField: Int? = nil
    static var caretOn = true
    /// Pushed NavigationLink destinations (top = visible page).
    static var navStack: [() -> any View] = []

    static func beginPass() {
        scrollCounter = 0
        fieldCounter = 0
    }

    static func nextScrollID() -> Int { scrollCounter += 1; return scrollCounter }
    static func nextFieldID() -> Int { fieldCounter += 1; return fieldCounter }

    static func push(_ destination: @escaping () -> any View) {
        navStack.append(destination)
        scrollOffsets = [:]
        focusedField = nil
        invalidate()
    }

    static func pop() {
        guard !navStack.isEmpty else { return }
        navStack.removeLast()
        // Pages above the new top lose their @State, like SwiftUI destroying popped views
        for ns in stateSpaces.keys where ns > navStack.count { stateSpaces[ns] = nil }
        scrollOffsets = [:]
        focusedField = nil
        invalidate()
    }
}

// MARK: - Scrolling

class ScrollNode: WrapperNode, ClippingNode {
    let id = Runtime.nextScrollID()
    var contentHeight = 0.0
    var clipRect: Rect { frame }

    override func flexible(_ a: Axis) -> Bool { true }

    override func sizeThatFits(_ p: Proposal, _ g: Graphics) -> Size {
        let cs = child.sizeThatFits(Proposal(w: p.w, h: nil), g)
        return Size(w: p.w ?? cs.w, h: p.h ?? cs.h)
    }

    var offset: Double {
        get { Runtime.scrollOffsets[id] ?? 0 }
        set { Runtime.scrollOffsets[id] = min(max(0, newValue), max(0, contentHeight - frame.h)) }
    }

    override func place(_ r: Rect, _ g: Graphics) {
        frame = r
        let cs = child.sizeThatFits(Proposal(w: r.w, h: nil), g)
        contentHeight = cs.h
        offset = offset   // re-clamp after content size changes
        child.place(Rect(x: r.x + (r.w - min(cs.w, r.w)) / 2, y: r.y - offset, w: min(cs.w, r.w), h: cs.h), g)
    }

    override func draw(_ g: Graphics) {
        g.pushClip(frame)
        child.draw(g)
        g.popClip()
        drawIndicator(g)
    }

    func drawIndicator(_ g: Graphics) {
        guard contentHeight > frame.h + 1, Runtime.scrolling == id else { return }
        let h = max(36, frame.h * frame.h / contentHeight)
        let y = frame.y + (frame.h - h) * (offset / (contentHeight - frame.h))
        g.fillRoundRect(Rect(x: frame.x + frame.w - 6, y: y, w: 3, h: h), radius: 1.5, color: Color(150, 150, 155))
    }
}

// MARK: - List (iOS inset-grouped style)

struct ListSection {
    var header: String?
    var footer: String?
    var rows: [Node]
}

final class ListRowNode: TapNode {
    let push: (() -> any View)?
    let action: (() -> Void)?
    var first = false, last = false
    override var cursorHand: Bool { push != nil || action != nil }
    init(child: Node, push: (() -> any View)?, action: (() -> Void)?) {
        self.push = push; self.action = action
        super.init(child: child)
    }
    override func tap(x: Double, y: Double) {
        if let push { Runtime.push(push) } else { action?() }
    }
}

final class ListNode: ScrollNode {
    static let margin = 16.0, inset = 20.0, radius = 10.0
    let sections: [ListSection]
    private let body: Node

    init(sections: [ListSection]) {
        self.sections = sections
        // Rows are kept in a flat container so traversal (taps, colors) sees them
        let rows = sections.flatMap(\.rows)
        body = StackNode(axis: .vertical, spacing: 0, children: rows)
        super.init(child: body)
    }

    private func rowHeight(_ row: Node, width: Double, _ g: Graphics) -> Double {
        let content = (row as? ListRowNode)?.child ?? row
        let extra = (row as? ListRowNode)?.push != nil ? 24.0 : 0
        let s = content.sizeThatFits(Proposal(w: width - 2 * ListNode.inset - extra, h: nil), g)
        return max(44, s.h + 22)
    }

    private func headerHeight(_ s: ListSection, first: Bool) -> Double {
        s.header != nil ? (first ? 38 : 50) : (first ? 20 : 35)
    }

    private func layoutHeight(width: Double, _ g: Graphics) -> Double {
        let cardW = width - 2 * ListNode.margin
        var y = 0.0
        for (i, s) in sections.enumerated() {
            y += headerHeight(s, first: i == 0)
            y += s.rows.map { rowHeight($0, width: cardW, g) }.reduce(0, +)
            if s.footer != nil { y += 32 }
        }
        return y + 30
    }

    override func sizeThatFits(_ p: Proposal, _ g: Graphics) -> Size {
        Size(w: p.w ?? 360, h: p.h ?? layoutHeight(width: p.w ?? 360, g))
    }

    override func place(_ r: Rect, _ g: Graphics) {
        frame = r
        body.frame = r
        Runtime.screenBackground = .groupedBackground
        let cardW = r.w - 2 * ListNode.margin
        contentHeight = layoutHeight(width: r.w, g)
        offset = offset
        var y = r.y - offset
        for (i, s) in sections.enumerated() {
            y += headerHeight(s, first: i == 0)
            for (j, row) in s.rows.enumerated() {
                let h = rowHeight(row, width: cardW, g)
                let rowRect = Rect(x: r.x + ListNode.margin, y: y, w: cardW, h: h)
                row.frame = rowRect
                let content = (row as? ListRowNode)?.child ?? row
                let extra = (row as? ListRowNode)?.push != nil ? 24.0 : 0
                let cw = cardW - 2 * ListNode.inset - extra
                let cs = content.sizeThatFits(Proposal(w: cw, h: nil), g)
                // Rows fill their width when the content is flexible (Toggle, TextField, HStack+Spacer)
                let w = content.flexible(.horizontal) ? cw : min(cs.w, cw)
                content.place(Rect(x: rowRect.x + ListNode.inset, y: y + (h - cs.h) / 2, w: w, h: cs.h), g)
                if let lr = row as? ListRowNode { lr.first = j == 0; lr.last = j == s.rows.count - 1 }
                y += h
            }
            if s.footer != nil { y += 32 }
        }
    }

    override func draw(_ g: Graphics) {
        g.fillRoundRect(frame, radius: 0, color: .groupedBackground)
        g.pushClip(frame)
        let cardW = frame.w - 2 * ListNode.margin
        for s in sections {
            guard let firstRow = s.rows.first, let lastRow = s.rows.last else { continue }
            let top = firstRow.frame.y, bottom = lastRow.frame.y + lastRow.frame.h
            if let h = s.header {
                g.drawText(h, x: frame.x + ListNode.margin + ListNode.inset, y: top - 25, size: 13, weight: 400, color: Color(127, 127, 131))
            }
            g.fillRoundRect(Rect(x: frame.x + ListNode.margin, y: top, w: cardW, h: bottom - top), radius: ListNode.radius, color: .white)
            for (j, row) in s.rows.enumerated() {
                if let lr = row as? ListRowNode, lr.pressed, lr.cursorHand {
                    let rr = lr.first && lr.last ? ListNode.radius : 0
                    g.fillRoundRect(lr.frame, radius: rr, color: .rowHighlight)
                }
                ((row as? ListRowNode)?.child ?? row).draw(g)
                if let lr = row as? ListRowNode, lr.push != nil {
                    let size = 13.0
                    g.drawText(String(UnicodeScalar(0xE76C)!), x: lr.frame.x + lr.frame.w - 30,
                               y: lr.frame.y + (lr.frame.h - size) / 2, size: size, weight: 400,
                               color: Color(196, 196, 199), face: "Segoe Fluent Icons")
                }
                if j < s.rows.count - 1 {
                    g.hairline(x: row.frame.x + ListNode.inset, y: row.frame.y + row.frame.h - 0.5,
                               w: row.frame.w - ListNode.inset, color: .separator)
                }
            }
            if let f = s.footer {
                g.drawText(f, x: frame.x + ListNode.margin + ListNode.inset, y: bottom + 7, size: 13, weight: 400, color: Color(127, 127, 131))
            }
        }
        g.popClip()
        drawIndicator(g)
    }
}

// MARK: - Navigation

final class BackButtonNode: TapNode {
    override func tap(x: Double, y: Double) { Runtime.pop() }
    override func draw(_ g: Graphics) {
        if pressed { applyAlpha(child) }
        child.draw(g)
    }
}

final class NavStackNode: Node {
    let page: Node
    let title: String?
    let backTitle: String?
    let back: BackButtonNode?
    let large: Bool
    override var children: [Node] { [page] + (back.map { [$0] } ?? []) }

    init(page: Node, title: String?, backTitle: String?) {
        self.page = page
        self.title = title
        self.backTitle = backTitle
        self.large = backTitle == nil && title != nil
        if let backTitle {
            let label = StackNode(axis: .horizontal, spacing: 4, children: [
                { let t = TextNode(text: String(UnicodeScalar(0xE76B)!), size: 19, weight: 400, color: .accentColor)
                  t.face = "Segoe Fluent Icons"; return t }(),
                TextNode(text: backTitle, size: 17, weight: 400, color: .accentColor),
            ])
            back = BackButtonNode(child: label)
        } else {
            back = nil
        }
    }

    var barHeight: Double { large ? 96 : 44 }

    override func flexible(_ a: Axis) -> Bool { true }
    override func sizeThatFits(_ p: Proposal, _ g: Graphics) -> Size { Size(w: p.w ?? 360, h: p.h ?? 640) }

    override func place(_ r: Rect, _ g: Graphics) {
        frame = r
        let area = Rect(x: r.x, y: r.y + barHeight, w: r.w, h: r.h - barHeight)
        let s = page.sizeThatFits(Proposal(w: area.w, h: area.h), g)
        // Non-filling pages sit at the top like a VStack in a navigation view, centered horizontally
        let w = min(s.w, area.w), h = min(s.h, area.h)
        page.place(Rect(x: area.x + (area.w - w) / 2, y: area.y + (page.flexible(.vertical) ? 0 : (area.h - h) / 2), w: w, h: h), g)
        if let back {
            let bs = back.sizeThatFits(.ideal, g)
            back.place(Rect(x: r.x + 8, y: r.y + (44 - bs.h) / 2, w: bs.w, h: bs.h), g)
        }
    }

    override func draw(_ g: Graphics) {
        page.draw(g)
        // Bar background matches the page (grouped lists are gray)
        let bg = Runtime.screenBackground
        g.fillRoundRect(Rect(x: frame.x, y: frame.y - 62, w: frame.w, h: barHeight + 62), radius: 0, color: bg)
        if let title {
            if large {
                g.drawText(title, x: frame.x + 16, y: frame.y + 44, size: 34, weight: 700, color: .black)
            } else {
                let s = g.measureText(title, size: 17, weight: 600)
                g.drawText(title, x: frame.x + (frame.w - s.w) / 2, y: frame.y + (44 - s.h) / 2, size: 17, weight: 600, color: .black)
            }
        }
        back?.draw(g)
    }
}

/// First .navigationTitle found in a page's tree.
func findTitle(_ n: Node) -> String? {
    if let t = n as? NavTitleNode { return t.title }
    for c in n.children { if let t = findTitle(c) { return t } }
    return nil
}

// MARK: - TextField

final class TextFieldNode: TapNode {
    let id = Runtime.nextFieldID()
    let placeholder: String
    let text: Binding<String>
    var rounded = false
    override var cursorHand: Bool { false }

    init(placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self.text = text
        super.init(child: Node())
    }

    var focused: Bool { Runtime.focusedField == id }

    override func flexible(_ a: Axis) -> Bool { a == .horizontal }
    override func sizeThatFits(_ p: Proposal, _ g: Graphics) -> Size {
        let s = g.measureText(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue, size: 17, weight: 400)
        let pad = rounded ? 7.0 : 0
        return Size(w: p.w ?? (s.w + 2 * pad + 4), h: 22 + 2 * pad)
    }

    override func tap(x: Double, y: Double) {
        Runtime.focusedField = id
        Runtime.caretOn = true
    }

    func key(_ ch: UInt16) {
        var v = text.wrappedValue
        switch ch {
        case 8: if !v.isEmpty { v.removeLast() }
        case 13, 27: Runtime.focusedField = nil; return
        default:
            guard ch >= 32, let u = UnicodeScalar(ch) else { return }
            v.append(Character(u))
        }
        text.wrappedValue = v
    }

    override func draw(_ g: Graphics) {
        let pad = rounded ? 7.0 : 0
        if rounded {
            g.fillRoundRect(frame, radius: 5, color: .white)
            g.strokeRoundRect(frame, radius: 5, color: Color(204, 204, 208))
        }
        let value = text.wrappedValue
        let x = frame.x + pad, y = frame.y + pad
        if value.isEmpty {
            g.drawText(placeholder, x: x, y: y, size: 17, weight: 400, color: .placeholder)
        } else {
            g.drawText(value, x: x, y: y, size: 17, weight: 400, color: .black)
        }
        if focused && Runtime.caretOn {
            let w = value.isEmpty ? 0 : g.measureText(value, size: 17, weight: 400).w
            g.fillRoundRect(Rect(x: x + w + 1, y: y + 1, w: 2, h: 21), radius: 1, color: .accentColor)
        }
    }
}

// MARK: - Toggle

final class ToggleNode: TapNode {
    let isOn: Binding<Bool>
    init(label: Node, isOn: Binding<Bool>) { self.isOn = isOn; super.init(child: label) }

    override func flexible(_ a: Axis) -> Bool { a == .horizontal }
    override func sizeThatFits(_ p: Proposal, _ g: Graphics) -> Size {
        let l = child.sizeThatFits(Proposal(w: p.w.map { max(0, $0 - 59) }, h: nil), g)
        return Size(w: p.w ?? (l.w + 59), h: max(31, l.h))
    }
    override func place(_ r: Rect, _ g: Graphics) {
        frame = r
        let l = child.sizeThatFits(Proposal(w: max(0, r.w - 59), h: nil), g)
        child.place(Rect(x: r.x, y: r.y + (r.h - l.h) / 2, w: min(l.w, r.w - 59), h: l.h), g)
    }
    override func tap(x: Double, y: Double) { isOn.wrappedValue.toggle() }
    override func draw(_ g: Graphics) {
        child.draw(g)
        let on = isOn.wrappedValue
        let sw = Rect(x: frame.x + frame.w - 51, y: frame.y + (frame.h - 31) / 2, w: 51, h: 31)
        g.fillRoundRect(sw, radius: 15.5, color: on ? .green : .switchOff)
        let knob = Rect(x: on ? sw.x + 22 : sw.x + 2, y: sw.y + 2, w: 27, h: 27)
        g.fillEllipse(Rect(x: knob.x - 0.5, y: knob.y + 0.5, w: 28, h: 28), color: Color(210, 210, 214))
        g.fillEllipse(knob, color: .white)
    }
}

// MARK: - Scroll hit-testing and drag state

extension Runtime {
    static var scrollNodes: [ScrollNode] = []
    static var drag: (scrollID: Int, startY: Double, startOffset: Double)? = nil
    static var dragging = false

    static func collectScrolls(_ n: Node) {
        if let s = n as? ScrollNode { scrollNodes.append(s) }
        n.children.forEach(collectScrolls)
    }

    /// Innermost scroll view under the point.
    static func scrollNode(atX x: Double, y: Double) -> ScrollNode? {
        scrollNodes.last { $0.frame.contains(x, y) }
    }
}
