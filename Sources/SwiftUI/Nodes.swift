// Render tree with SwiftUI-style layout: a parent proposes a size, the child
// answers with the size it wants (sizeThatFits), then the parent places it.

struct Size { var w = 0.0, h = 0.0 }

struct Rect {
    var x = 0.0, y = 0.0, w = 0.0, h = 0.0
    func contains(_ px: Double, _ py: Double) -> Bool { px >= x && px < x + w && py >= y && py < y + h }
    func intersection(_ o: Rect) -> Rect {
        let x0 = max(x, o.x), y0 = max(y, o.y)
        let x1 = min(x + w, o.x + o.w), y1 = min(y + h, o.y + o.h)
        return Rect(x: x0, y: y0, w: max(0, x1 - x0), h: max(0, y1 - y0))
    }
}

/// nil = "use your ideal size" on that axis.
struct Proposal {
    var w: Double?
    var h: Double?
    static let ideal = Proposal(w: nil, h: nil)
}

public enum Axis { case horizontal, vertical }

class Node {
    var frame = Rect()
    var children: [Node] { [] }

    func sizeThatFits(_ p: Proposal, _ g: Graphics) -> Size { Size() }
    func place(_ r: Rect, _ g: Graphics) { frame = r }
    /// Whether this node grows to fill extra space offered along `axis`.
    func flexible(_ axis: Axis) -> Bool { children.contains { $0.flexible(axis) } }
    func draw(_ g: Graphics) { children.forEach { $0.draw(g) } }
}

// MARK: - Leaf nodes

final class TextNode: Node {
    let text: String
    var size: Double
    var weight: Int
    var color: Color
    var face = "Segoe UI"
    var explicitColor = false
    var explicitFont = false
    var centered = false
    init(text: String, size: Double, weight: Int, color: Color) {
        self.text = text; self.size = size; self.weight = weight; self.color = color
    }
    override func sizeThatFits(_ p: Proposal, _ g: Graphics) -> Size {
        let one = g.measureText(text, size: size, weight: weight, face: face)
        guard let w = p.w, one.w > w, w > 0 else { return one }
        return g.measureWrapped(text, width: w, size: size, weight: weight, face: face)
    }
    override func draw(_ g: Graphics) {
        g.drawWrapped(text, in: frame, size: size, weight: weight, color: color, face: face, centered: centered)
    }
}

final class SpacerNode: Node {
    let minLength: Double
    var axis: Axis? = nil            // set by the enclosing stack
    init(length: Double) { self.minLength = length }
    override func flexible(_ a: Axis) -> Bool { axis == nil || axis == a }
    override func sizeThatFits(_ p: Proposal, _ g: Graphics) -> Size {
        switch axis {
        case .vertical?:   return Size(w: 0, h: max(minLength, p.h ?? minLength))
        case .horizontal?: return Size(w: max(minLength, p.w ?? minLength), h: 0)
        case nil:          return Size(w: p.w ?? minLength, h: p.h ?? minLength)
        }
    }
}

/// Color / Rectangle / RoundedRectangle / Circle: fill whatever is proposed.
final class ShapeNode: Node {
    enum Kind { case rect, rounded(Double), circle, capsule }
    let kind: Kind
    var color: Color
    var explicitColor = false
    init(kind: Kind, color: Color) { self.kind = kind; self.color = color }
    override func flexible(_ a: Axis) -> Bool { true }
    override func sizeThatFits(_ p: Proposal, _ g: Graphics) -> Size { Size(w: p.w ?? 10, h: p.h ?? 10) }
    override func draw(_ g: Graphics) {
        switch kind {
        case .rect: g.fillRoundRect(frame, radius: 0, color: color)
        case .rounded(let r): g.fillRoundRect(frame, radius: r, color: color)
        case .capsule: g.fillRoundRect(frame, radius: min(frame.w, frame.h) / 2, color: color)
        case .circle:
            let d = min(frame.w, frame.h)
            g.fillEllipse(Rect(x: frame.x + (frame.w - d) / 2, y: frame.y + (frame.h - d) / 2, w: d, h: d), color: color)
        }
    }
}

final class DividerNode: Node {
    var axis: Axis = .vertical       // inside a VStack the line is horizontal
    override func flexible(_ a: Axis) -> Bool { a == (axis == .vertical ? .horizontal : .vertical) }
    override func sizeThatFits(_ p: Proposal, _ g: Graphics) -> Size {
        axis == .vertical ? Size(w: p.w ?? 0, h: 0.5) : Size(w: 0.5, h: p.h ?? 0)
    }
    override func draw(_ g: Graphics) { g.fillRoundRect(frame, radius: 0, color: Color(198, 198, 200)) }
}

// MARK: - Stacks

final class StackNode: Node {
    let axis: Axis
    let spacing: Double
    let items: [Node]
    let hAlign: HorizontalAlignment
    let vAlign: VerticalAlignment
    override var children: [Node] { items }

    init(axis: Axis, spacing: Double, children: [Node], hAlign: HorizontalAlignment = .center, vAlign: VerticalAlignment = .center) {
        self.axis = axis; self.spacing = spacing; self.items = children; self.hAlign = hAlign; self.vAlign = vAlign
        super.init()
        for c in children {
            if let s = c as? SpacerNode { s.axis = axis }
            if let d = c as? DividerNode { d.axis = axis }
        }
    }

    private func main(_ s: Size) -> Double { axis == .vertical ? s.h : s.w }
    private func cross(_ s: Size) -> Double { axis == .vertical ? s.w : s.h }
    private func proposal(main m: Double?, cross c: Double?) -> Proposal {
        axis == .vertical ? Proposal(w: c, h: m) : Proposal(w: m, h: c)
    }

    /// Fixed children get their ideal main size; flexible ones share what's left.
    private func childSizes(_ p: Proposal, _ g: Graphics) -> [Size] {
        let crossP = axis == .vertical ? p.w : p.h
        let mainP = axis == .vertical ? p.h : p.w
        let gaps = spacing * Double(max(0, items.count - 1))
        var sizes = [Size?](repeating: nil, count: items.count)
        var used = gaps
        var flexIdx: [Int] = []
        for (i, c) in items.enumerated() {
            if c.flexible(axis) && mainP != nil { flexIdx.append(i); continue }
            let s = c.sizeThatFits(proposal(main: nil, cross: crossP), g)
            sizes[i] = s
            used += main(s)
        }
        if !flexIdx.isEmpty {
            var remaining = max(0, (mainP ?? 0) - used)
            var left = flexIdx.count
            for i in flexIdx {
                let share = remaining / Double(left)
                let s = items[i].sizeThatFits(proposal(main: share, cross: crossP), g)
                sizes[i] = s
                remaining -= main(s)
                left -= 1
            }
        }
        return sizes.map { $0! }
    }

    override func sizeThatFits(_ p: Proposal, _ g: Graphics) -> Size {
        let sizes = childSizes(p, g)
        let gaps = spacing * Double(max(0, items.count - 1))
        let m = sizes.map(main).reduce(0, +) + gaps
        let c = sizes.map(cross).max() ?? 0
        return axis == .vertical ? Size(w: c, h: m) : Size(w: m, h: c)
    }

    override func place(_ r: Rect, _ g: Graphics) {
        frame = r
        let sizes = childSizes(Proposal(w: r.w, h: r.h), g)
        var cursor = axis == .vertical ? r.y : r.x
        for (c, s) in zip(items, sizes) {
            switch axis {
            case .vertical:
                let cw = min(s.w, r.w)
                let x: Double
                switch hAlign {
                case .leading: x = r.x
                case .center: x = r.x + (r.w - cw) / 2
                case .trailing: x = r.x + r.w - cw
                }
                c.place(Rect(x: x, y: cursor, w: cw, h: s.h), g)
                cursor += s.h + spacing
            case .horizontal:
                let ch = min(s.h, r.h)
                let y: Double
                switch vAlign {
                case .top: y = r.y
                case .center: y = r.y + (r.h - ch) / 2
                case .bottom: y = r.y + r.h - ch
                }
                c.place(Rect(x: cursor, y: y, w: s.w, h: ch), g)
                cursor += s.w + spacing
            }
        }
    }
}

/// ZStack: children layered, aligned to center.
final class LayerNode: Node {
    let items: [Node]
    override var children: [Node] { items }
    init(children: [Node]) { self.items = children }
    override func sizeThatFits(_ p: Proposal, _ g: Graphics) -> Size {
        let sizes = items.map { $0.sizeThatFits(p, g) }
        return Size(w: sizes.map(\.w).max() ?? 0, h: sizes.map(\.h).max() ?? 0)
    }
    override func place(_ r: Rect, _ g: Graphics) {
        frame = r
        for c in items {
            let s = c.sizeThatFits(Proposal(w: r.w, h: r.h), g)
            c.place(Rect(x: r.x + (r.w - s.w) / 2, y: r.y + (r.h - s.h) / 2, w: min(s.w, r.w), h: min(s.h, r.h)), g)
        }
    }
}

// MARK: - Modifier nodes

class WrapperNode: Node {
    let child: Node
    override var children: [Node] { [child] }
    init(child: Node) { self.child = child }
    override func sizeThatFits(_ p: Proposal, _ g: Graphics) -> Size { child.sizeThatFits(p, g) }
    override func place(_ r: Rect, _ g: Graphics) { frame = r; child.place(r, g) }
}

final class PaddingNode: WrapperNode {
    let top: Double, leading: Double, bottom: Double, trailing: Double
    init(top: Double, leading: Double, bottom: Double, trailing: Double, child: Node) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
        super.init(child: child)
    }
    override func sizeThatFits(_ p: Proposal, _ g: Graphics) -> Size {
        let inner = Proposal(w: p.w.map { max(0, $0 - leading - trailing) }, h: p.h.map { max(0, $0 - top - bottom) })
        let s = child.sizeThatFits(inner, g)
        return Size(w: s.w + leading + trailing, h: s.h + top + bottom)
    }
    override func place(_ r: Rect, _ g: Graphics) {
        frame = r
        child.place(Rect(x: r.x + leading, y: r.y + top, w: max(0, r.w - leading - trailing), h: max(0, r.h - top - bottom)), g)
    }
}

final class FrameNode: WrapperNode {
    let width: Double?, height: Double?
    let maxWidth: Double?, maxHeight: Double?
    let hAlign: HorizontalAlignment, vAlign: VerticalAlignment
    init(width: Double?, height: Double?, maxWidth: Double?, maxHeight: Double?,
         hAlign: HorizontalAlignment, vAlign: VerticalAlignment, child: Node) {
        self.width = width; self.height = height; self.maxWidth = maxWidth; self.maxHeight = maxHeight
        self.hAlign = hAlign; self.vAlign = vAlign
        super.init(child: child)
    }
    override func flexible(_ a: Axis) -> Bool {
        switch a {
        case .horizontal: return width == nil && (maxWidth != nil || child.flexible(a))
        case .vertical: return height == nil && (maxHeight != nil || child.flexible(a))
        }
    }
    override func sizeThatFits(_ p: Proposal, _ g: Graphics) -> Size {
        let pw = width ?? p.w.map { min($0, maxWidth ?? .infinity) }
        let ph = height ?? p.h.map { min($0, maxHeight ?? .infinity) }
        let s = child.sizeThatFits(Proposal(w: pw, h: ph), g)
        var w = width ?? s.w
        var h = height ?? s.h
        if width == nil, let mw = maxWidth, let pw = p.w { w = min(mw, max(s.w, pw)) }
        if height == nil, let mh = maxHeight, let ph = p.h { h = min(mh, max(s.h, ph)) }
        return Size(w: w, h: h)
    }
    override func place(_ r: Rect, _ g: Graphics) {
        frame = r
        let s = child.sizeThatFits(Proposal(w: r.w, h: r.h), g)
        let cw = min(s.w, r.w), ch = min(s.h, r.h)
        let x: Double = hAlign == .leading ? r.x : hAlign == .trailing ? r.x + r.w - cw : r.x + (r.w - cw) / 2
        let y: Double = vAlign == .top ? r.y : vAlign == .bottom ? r.y + r.h - ch : r.y + (r.h - ch) / 2
        child.place(Rect(x: x, y: y, w: cw, h: ch), g)
    }
}

final class BackgroundNode: WrapperNode {
    let color: Color
    var radius: Double
    init(color: Color, radius: Double, child: Node) { self.color = color; self.radius = radius; super.init(child: child) }
    override func draw(_ g: Graphics) {
        g.fillRoundRect(frame, radius: radius, color: color)
        child.draw(g)
    }
}

/// Carries .navigationTitle up to the enclosing NavigationStack.
final class NavTitleNode: WrapperNode {
    let title: String
    init(title: String, child: Node) { self.title = title; super.init(child: child) }
}

// MARK: - Interactive nodes

/// Anything that reacts to clicks. `clip` is the visible area (scroll views clip their content).
class TapNode: WrapperNode {
    var hovered = false
    var pressed = false
    var clip: Rect? = nil
    var cursorHand: Bool { true }
    func tap(x: Double, y: Double) {}
}

final class ButtonNode: TapNode {
    let action: () -> Void
    init(action: @escaping () -> Void, child: Node) { self.action = action; super.init(child: child) }
    override func tap(x: Double, y: Double) { action() }
    override func draw(_ g: Graphics) {
        if Runtime.iOSStyle {
            if pressed { applyAlpha(child) }
            child.draw(g)
            return
        }
        let c = pressed ? Color(0, 96, 210) : hovered ? Color(30, 140, 255) : Color.accentColor
        g.fillRoundRect(frame, radius: 8, color: c)
        child.draw(g)
    }
}

/// Pressed iOS buttons render their label lighter.
func applyAlpha(_ node: Node) {
    func lighten(_ c: Color) -> Color {
        Color(UInt8((Int(c.r) + 255 * 2) / 3), UInt8((Int(c.g) + 255 * 2) / 3), UInt8((Int(c.b) + 255 * 2) / 3))
    }
    if let t = node as? TextNode { t.color = lighten(t.color) }
    if let s = node as? ShapeNode { s.color = lighten(s.color) }
    node.children.forEach(applyAlpha)
}

/// Nodes that clip their content (scroll views, lists); clicks outside the clip are ignored.
protocol ClippingNode: AnyObject {
    var clipRect: Rect { get }
}
