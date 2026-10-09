// Public SwiftUI API surface: View, App, Scene, builders, state, primitives.

public protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Body { get }
}

extension Never: View {
    public var body: Never { fatalError("Never has no body") }
}

/// Views that render themselves instead of composing a body.
protocol PrimitiveView {
    func makeNode() -> Node
}

// MARK: - App / Scene

public protocol Scene {}

public protocol App {
    associatedtype Body: Scene
    var body: Body { get }
    init()
}

extension App {
    public static func main() {
        let app = Self()
        guard let group = app.body as? any WindowGroupProtocol else {
            fatalError("Only WindowGroup scenes are supported")
        }
        Runtime.run(title: group.title ?? String(describing: Self.self), content: group.makeRoot)
    }
}

protocol WindowGroupProtocol {
    var title: String? { get }
    func makeRoot() -> any View
}

public struct WindowGroup<Content: View>: Scene, WindowGroupProtocol {
    let title: String?
    let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.title = nil
        self.content = content
    }

    public init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    func makeRoot() -> any View { content() }
}

// MARK: - ViewBuilder

@resultBuilder
public enum ViewBuilder {
    public static func buildBlock() -> EmptyView { EmptyView() }

    // A single child is returned as-is (also lets `body: Never { fatalError() }` type-check)
    public static func buildBlock<C: View>(_ content: C) -> C { content }

    public static func buildBlock<each C: View>(_ content: repeat each C) -> TupleView {
        var children: [any View] = []
        repeat children.append(each content)
        return TupleView(children)
    }

    public static func buildOptional<C: View>(_ c: C?) -> C? { c }
    public static func buildEither<T: View, F: View>(first: T) -> EitherView<T, F> { EitherView(first: first) }
    public static func buildEither<T: View, F: View>(second: F) -> EitherView<T, F> { EitherView(second: second) }
}

public struct EmptyView: View, PrimitiveView {
    public init() {}
    public var body: Never { fatalError() }
    func makeNode() -> Node { StackNode(axis: .vertical, spacing: 0, children: []) }
}

extension EmptyView: MultiView { var views: [any View] { [] } }

/// Views that stand for zero or more sibling views (builder blocks, if/else, ForEach, Group).
/// Stacks and lists splice them into their own children.
protocol MultiView {
    var views: [any View] { get }
}

public struct TupleView: View, PrimitiveView, MultiView {
    let children: [any View]
    init(_ children: [any View]) { self.children = children }
    var views: [any View] { children }
    public var body: Never { fatalError() }
    func makeNode() -> Node { StackNode(axis: .vertical, spacing: 0, children: flatten(self)) }
}

extension Optional: View where Wrapped: View {
    public var body: Never { fatalError() }
}

extension Optional: PrimitiveView, MultiView where Wrapped: View {
    var views: [any View] { map { [$0] } ?? [] }
    func makeNode() -> Node {
        if let v = self { return resolve(v) }
        return StackNode(axis: .vertical, spacing: 0, children: [])
    }
}

public struct EitherView<T: View, F: View>: View, PrimitiveView, MultiView {
    let first: T?, second: F?
    init(first: T) { self.first = first; self.second = nil }
    init(second: F) { self.first = nil; self.second = second }
    var views: [any View] { first.map { [$0] } ?? [second!] }
    public var body: Never { fatalError() }
    func makeNode() -> Node { first.map(resolve) ?? resolve(second!) }
}

/// Turn any view into a render node: primitives render, composites recurse into body.
func resolve(_ view: any View) -> Node {
    if let p = view as? PrimitiveView { return p.makeNode() }
    return resolve(view.body)
}

// MARK: - State

/// Storage is positional (like React hooks): the Nth @State created during a
/// render pass gets slot N. Works while the view tree's shape is stable.
@propertyWrapper
public struct State<Value> {
    final class Box { var value: Value; init(_ v: Value) { value = v } }
    let box: Box

    public init(wrappedValue: Value) {
        box = Runtime.stateSlot { Box(wrappedValue) }
    }

    public var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue; Runtime.invalidate() }
    }

    public var projectedValue: Binding<Value> {
        let box = self.box
        return Binding(get: { box.value }, set: { box.value = $0; Runtime.invalidate() })
    }
}

@propertyWrapper
public struct Binding<Value> {
    let get: () -> Value
    let set: (Value) -> Void
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) { self.get = get; self.set = set }
    public var wrappedValue: Value {
        get { get() }
        nonmutating set { set(newValue) }
    }
}

// MARK: - Color / Font

public struct Color: Equatable {
    let r: UInt8, g: UInt8, b: UInt8
    public init(red: Double, green: Double, blue: Double) {
        r = UInt8(max(0, min(255, red * 255))); g = UInt8(max(0, min(255, green * 255))); b = UInt8(max(0, min(255, blue * 255)))
    }
    init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }

    // macOS system colors (light mode)
    public static let primary = Color(29, 29, 31)
    public static let secondary = Color(110, 110, 115)
    public static let blue = Color(0, 122, 255)
    public static let red = Color(255, 59, 48)
    public static let green = Color(52, 199, 89)
    public static let orange = Color(255, 149, 0)
    public static let purple = Color(175, 82, 222)
    public static let white = Color(255, 255, 255)
    public static let black = Color(0, 0, 0)
    public static let gray = Color(142, 142, 147)
    public static let accentColor = blue
}

public struct Font: Equatable {
    let size: Double
    let weight: Int
    public static let largeTitle = Font(size: 34, weight: 400)
    public static let title = Font(size: 28, weight: 400)
    public static let title2 = Font(size: 22, weight: 400)
    public static let title3 = Font(size: 20, weight: 400)
    public static let headline = Font(size: 17, weight: 600)
    public static let body = Font(size: 17, weight: 400)
    public static let callout = Font(size: 16, weight: 400)
    public static let caption = Font(size: 12, weight: 400)
    public static func system(size: Double) -> Font { Font(size: size, weight: 400) }
}

// MARK: - Text

public struct Text: View, PrimitiveView {
    let content: String
    var font: Font?
    var isBold = false
    var color: Color?

    public init(_ content: String) { self.content = content }
    public init<S: StringProtocol>(_ content: S) { self.content = String(content) }

    public var body: Never { fatalError() }

    public func font(_ f: Font?) -> Text { var t = self; t.font = f; return t }
    public func bold() -> Text { var t = self; t.isBold = true; return t }
    public func foregroundColor(_ c: Color?) -> Text { var t = self; t.color = c; return t }
    public func foregroundStyle<S: ShapeStyle>(_ s: S) -> Text { var t = self; t.color = s.resolvedColor; return t }

    func makeNode() -> Node {
        let f = font ?? .body
        let n = TextNode(text: content, size: f.size, weight: isBold ? 700 : f.weight, color: color ?? .primary)
        n.explicitFont = font != nil
        n.explicitColor = color != nil
        return n
    }
}

// MARK: - ShapeStyle

public protocol ShapeStyle {
    var resolvedColor: Color { get }
}

extension Color: ShapeStyle {
    public var resolvedColor: Color { self }
}

public struct TintShapeStyle: ShapeStyle {
    public var resolvedColor: Color { .accentColor }
}

extension ShapeStyle where Self == TintShapeStyle {
    public static var tint: TintShapeStyle { TintShapeStyle() }
}

/// .primary / .secondary / .tertiary label colors (iOS light mode)
public struct HierarchicalShapeStyle: ShapeStyle {
    let level: Int
    public var resolvedColor: Color {
        switch level {
        case 0: return Color(0, 0, 0)
        case 1: return Color(127, 127, 131)     // secondaryLabel
        case 2: return Color(196, 196, 199)     // tertiaryLabel
        default: return Color(214, 214, 217)
        }
    }
}

extension ShapeStyle where Self == HierarchicalShapeStyle {
    public static var primary: HierarchicalShapeStyle { HierarchicalShapeStyle(level: 0) }
    public static var secondary: HierarchicalShapeStyle { HierarchicalShapeStyle(level: 1) }
    public static var tertiary: HierarchicalShapeStyle { HierarchicalShapeStyle(level: 2) }
    public static var quaternary: HierarchicalShapeStyle { HierarchicalShapeStyle(level: 3) }
}

// MARK: - Image (SF Symbols mapped to Segoe Fluent Icons)

public struct Image: View, PrimitiveView {
    public enum Scale { case small, medium, large }

    let systemName: String
    var scale: Scale = .medium
    var color: Color?

    public init(systemName: String) { self.systemName = systemName }

    public var body: Never { fatalError() }

    public func imageScale(_ s: Scale) -> Image { var i = self; i.scale = s; return i }
    public func foregroundStyle<S: ShapeStyle>(_ s: S) -> Image { var i = self; i.color = s.resolvedColor; return i }
    public func foregroundColor(_ c: Color?) -> Image { var i = self; i.color = c; return i }

    // SF Symbol name → Segoe Fluent Icons / MDL2 code point
    static let glyphs: [String: UInt32] = [
        "globe": 0xE774, "star": 0xE734, "star.fill": 0xE735, "heart": 0xEB51, "heart.fill": 0xEB52,
        "house": 0xE80F, "house.fill": 0xE80F, "gear": 0xE713, "gearshape": 0xE713, "gearshape.fill": 0xE713,
        "person": 0xE77B, "person.fill": 0xE77B, "person.circle": 0xE77B, "magnifyingglass": 0xE721,
        "plus": 0xE710, "minus": 0xE738, "trash": 0xE74D, "bell": 0xEA8F, "bell.fill": 0xEA8F,
        "checkmark": 0xE73E, "xmark": 0xE711, "camera": 0xE722, "camera.fill": 0xE722, "photo": 0xEB9F,
        "envelope": 0xE715, "phone": 0xE717, "phone.fill": 0xE717, "music.note": 0xE8D6,
        "play.fill": 0xE768, "pause.fill": 0xE769, "square.and.arrow.up": 0xE72D, "arrow.right": 0xE72A,
        "arrow.left": 0xE72B, "chevron.right": 0xE76C, "chevron.left": 0xE76B, "info.circle": 0xE946,
        "exclamationmark.triangle": 0xE7BA, "lock": 0xE72E, "lock.fill": 0xE72E, "map": 0xE707,
        "cart": 0xE7BF, "calendar": 0xE787, "clock": 0xE823, "sun.max": 0xE706, "moon": 0xE708,
        "cloud": 0xE753, "bolt": 0xE945, "wifi": 0xE701, "pencil": 0xE70F, "square.and.pencil": 0xE70F,
        "folder": 0xE8B7, "doc": 0xE8A5, "link": 0xE71B, "flag": 0xE7C1, "bookmark": 0xE8A4,
        "ellipsis": 0xE712, "list.bullet": 0xE8FD, "paperplane": 0xE724, "message": 0xE8BD,
    ]

    func makeNode() -> Node {
        let cp = Image.glyphs[systemName] ?? 0xE9CE   // unknown symbol placeholder
        let size: Double = scale == .large ? 22 : scale == .small ? 13 : 17
        let n = TextNode(text: String(UnicodeScalar(cp)!), size: size, weight: 400, color: color ?? .primary)
        n.face = "Segoe Fluent Icons"
        n.explicitColor = color != nil
        n.explicitFont = true
        return n
    }
}

// MARK: - Button

public struct Button<Label: View>: View, PrimitiveView {
    let action: () -> Void
    let label: Label

    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    public var body: Never { fatalError() }

    func makeNode() -> Node {
        var child = resolve(label)
        if Runtime.iOSStyle {
            // iOS default (automatic) button style: tinted label, no background
            applyForeground(child, .accentColor)
            return ButtonNode(action: action, child: child)
        }
        if let t = child as? TextNode { t.color = .white; t.weight = max(t.weight, 500) }
        child = PaddingNode(top: 7, leading: 16, bottom: 7, trailing: 16, child: child)
        return ButtonNode(action: action, child: child)
    }
}

extension Button where Label == Text {
    public init(_ title: String, action: @escaping () -> Void) {
        self.action = action
        self.label = Text(title)
    }
}

// MARK: - Stacks

public enum HorizontalAlignment { case leading, center, trailing }
public enum VerticalAlignment { case top, center, bottom }

public struct VStack<Content: View>: View, PrimitiveView {
    let alignment: HorizontalAlignment, spacing: Double?, content: Content
    public init(alignment: HorizontalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment; self.spacing = spacing; self.content = content()
    }
    public var body: Never { fatalError() }
    func makeNode() -> Node {
        StackNode(axis: .vertical, spacing: spacing ?? 8, children: flatten(content), hAlign: alignment)
    }
}

public struct HStack<Content: View>: View, PrimitiveView {
    let alignment: VerticalAlignment, spacing: Double?, content: Content
    public init(alignment: VerticalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment; self.spacing = spacing; self.content = content()
    }
    public var body: Never { fatalError() }
    func makeNode() -> Node {
        StackNode(axis: .horizontal, spacing: spacing ?? 8, children: flatten(content), vAlign: alignment)
    }
}

public struct Spacer: View, PrimitiveView {
    let minLength: Double?
    public init(minLength: Double? = nil) { self.minLength = minLength }
    public var body: Never { fatalError() }
    func makeNode() -> Node { SpacerNode(length: minLength ?? 8) }
}

/// A stack's builder content is a TupleView; its children become stack children.
func flatten(_ view: any View) -> [Node] {
    if let m = view as? MultiView { return m.views.flatMap(flatten) }
    return [resolve(view)]
}

/// Same splicing at the view level (List rows, Section contents).
func flattenViews(_ view: any View) -> [any View] {
    if let m = view as? MultiView { return m.views.flatMap(flattenViews) }
    return [view]
}

// MARK: - Modifiers

public struct ModifiedView: View, PrimitiveView {
    let make: () -> Node
    public var body: Never { fatalError() }
    func makeNode() -> Node { make() }
}

/// Environment-style propagation: fill in color/font on descendants that didn't set their own.
func applyForeground(_ node: Node, _ color: Color) {
    if let t = node as? TextNode, !t.explicitColor { t.color = color; t.explicitColor = true }
    node.children.forEach { applyForeground($0, color) }
}

func applyFont(_ node: Node, _ font: Font) {
    if let t = node as? TextNode, !t.explicitFont { t.size = font.size; t.weight = font.weight; t.explicitFont = true }
    node.children.forEach { applyFont($0, font) }
}

extension View {
    public func foregroundStyle<S: ShapeStyle>(_ s: S) -> ModifiedView {
        let v = self
        return ModifiedView { let n = resolve(v); applyForeground(n, s.resolvedColor); return n }
    }

    public func foregroundColor(_ c: Color?) -> ModifiedView {
        let v = self
        return ModifiedView { let n = resolve(v); if let c { applyForeground(n, c) }; return n }
    }

    public func font(_ f: Font?) -> ModifiedView {
        let v = self
        return ModifiedView { let n = resolve(v); if let f { applyFont(n, f) }; return n }
    }

    public func padding(_ length: Double = 16) -> ModifiedView {
        let v = self
        return ModifiedView { PaddingNode(top: length, leading: length, bottom: length, trailing: length, child: resolve(v)) }
    }

    public func background(_ color: Color) -> ModifiedView {
        let v = self
        return ModifiedView { BackgroundNode(color: color, radius: 0, child: resolve(v)) }
    }

    public func cornerRadius(_ r: Double) -> ModifiedView {
        let v = self
        return ModifiedView {
            let n = resolve(v)
            if let b = n as? BackgroundNode { b.radius = r }
            return n
        }
    }
}
