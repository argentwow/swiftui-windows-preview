// More of the public SwiftUI API: containers, navigation, controls, shapes, layout modifiers.

public typealias CGFloat = Double

extension Runtime {
    static var scrolling: Int? = nil   // scroll view currently being dragged/wheeled (shows indicator)
}

// MARK: - Grouping

public struct Group<Content: View>: View, PrimitiveView, MultiView {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    var views: [any View] { [content] }
    public var body: Never { fatalError() }
    func makeNode() -> Node { StackNode(axis: .vertical, spacing: 0, children: flatten(content)) }
}

public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: View, PrimitiveView, MultiView {
    let data: Data
    let content: (Data.Element) -> Content
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data; self.content = content
    }
    var views: [any View] { data.map { content($0) } }
    public var body: Never { fatalError() }
    func makeNode() -> Node { StackNode(axis: .vertical, spacing: 0, children: flatten(self)) }
}

extension ForEach where Data == Range<Int>, ID == Int {
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {
        self.data = data; self.content = content
    }
}

extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data; self.content = content
    }
}

public struct ZStack<Content: View>: View, PrimitiveView {
    let content: Content
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) { self.content = content() }
    public var body: Never { fatalError() }
    func makeNode() -> Node { LayerNode(children: flatten(content)) }
}

// MARK: - Scrolling and lists

public struct ScrollView<Content: View>: View, PrimitiveView {
    let content: Content
    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.content = content()
    }
    public var body: Never { fatalError() }
    func makeNode() -> Node {
        ScrollNode(child: StackNode(axis: .vertical, spacing: 8, children: flatten(content)))
    }
}

extension Axis {
    public struct Set: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let horizontal = Set(rawValue: 1)
        public static let vertical = Set(rawValue: 2)
    }
}

protocol SectionProtocol {
    var headerText: String? { get }
    var footerText: String? { get }
    var rows: [any View] { get }
}

public struct Section<Content: View>: View, PrimitiveView, SectionProtocol {
    let headerText: String?
    let footerText: String?
    let content: Content
    public init(@ViewBuilder content: () -> Content) { headerText = nil; footerText = nil; self.content = content() }
    public init(_ title: String, @ViewBuilder content: () -> Content) { headerText = title; footerText = nil; self.content = content() }
    public init(header: Text, @ViewBuilder content: () -> Content) { headerText = header.content; footerText = nil; self.content = content() }
    public init(header: Text, footer: Text, @ViewBuilder content: () -> Content) {
        headerText = header.content; footerText = footer.content; self.content = content()
    }
    public init(@ViewBuilder content: () -> Content, header: () -> Text) { headerText = header().content; footerText = nil; self.content = content() }
    public init(@ViewBuilder content: () -> Content, header: () -> Text, footer: () -> Text) {
        headerText = header().content; footerText = footer().content; self.content = content()
    }
    var rows: [any View] { flattenViews(content) }
    public var body: Never { fatalError() }
    func makeNode() -> Node { StackNode(axis: .vertical, spacing: 0, children: flatten(content)) }
}

public struct List<Content: View>: View, PrimitiveView {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: Never { fatalError() }

    func makeNode() -> Node {
        var sections: [ListSection] = []
        var loose: [Node] = []
        func flushLoose() {
            if !loose.isEmpty { sections.append(ListSection(header: nil, footer: nil, rows: loose)); loose = [] }
        }
        for v in flattenViews(content) {
            if let s = v as? SectionProtocol {
                flushLoose()
                sections.append(ListSection(header: s.headerText, footer: s.footerText, rows: s.rows.map(makeRow)))
            } else {
                loose.append(makeRow(v))
            }
        }
        flushLoose()
        return ListNode(sections: sections)
    }
}

public typealias Form = List

/// List rows: NavigationLinks push, Buttons fire their action, everything else is static.
func makeRow(_ v: any View) -> Node {
    if let link = v as? NavigationLinkProtocol {
        return ListRowNode(child: resolve(link.labelView), push: link.destinationBuilder, action: nil)
    }
    if let button = v as? ButtonProtocol {
        let label = resolve(button.labelView)
        applyForeground(label, .accentColor)
        return ListRowNode(child: label, push: nil, action: button.buttonAction)
    }
    return ListRowNode(child: resolve(v), push: nil, action: nil)
}

protocol ButtonProtocol {
    var labelView: any View { get }
    var buttonAction: () -> Void { get }
}

extension Button: ButtonProtocol {
    var labelView: any View { label }
    var buttonAction: () -> Void { action }
}

// MARK: - Navigation

public struct NavigationStack<Content: View>: View, PrimitiveView {
    let content: Content
    public init(@ViewBuilder root: () -> Content) { self.content = root() }
    public var body: Never { fatalError() }

    func makeNode() -> Node {
        let depth = Runtime.navStack.count
        let rootNode = resolve(content)
        let rootTitle = findTitle(rootNode)
        guard depth > 0 else {
            return NavStackNode(page: rootNode, title: rootTitle, backTitle: nil)
        }
        // Each pushed page keeps its own @State namespace
        let saved = Runtime.stateNamespace
        Runtime.stateNamespace = depth
        let pageNode = resolve(Runtime.navStack[depth - 1]())
        Runtime.stateNamespace = saved
        var backTitle = rootTitle ?? "Back"
        if depth >= 2 {
            Runtime.stateNamespace = depth - 1
            backTitle = findTitle(resolve(Runtime.navStack[depth - 2]())) ?? "Back"
            Runtime.stateNamespace = saved
        }
        return NavStackNode(page: pageNode, title: findTitle(pageNode), backTitle: backTitle)
    }
}

public typealias NavigationView = NavigationStack

protocol NavigationLinkProtocol {
    var labelView: any View { get }
    var destinationBuilder: () -> any View { get }
}

public struct NavigationLink<Label: View, Destination: View>: View, PrimitiveView, NavigationLinkProtocol {
    let label: Label
    let destination: Destination

    public init(destination: Destination, @ViewBuilder label: () -> Label) {
        self.destination = destination; self.label = label()
    }
    public init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
        self.destination = destination(); self.label = label()
    }

    var labelView: any View { label }
    var destinationBuilder: () -> any View { let d = destination; return { d } }

    public var body: Never { fatalError() }
    func makeNode() -> Node {
        // Outside a List a link looks like a button
        let l = resolve(label)
        applyForeground(l, .accentColor)
        let d = destination
        return ButtonNode(action: { Runtime.push { d } }, child: l)
    }
}

extension NavigationLink where Label == Text {
    public init(_ title: String, destination: Destination) {
        self.destination = destination; self.label = Text(title)
    }
    public init(_ title: String, @ViewBuilder destination: () -> Destination) {
        self.destination = destination(); self.label = Text(title)
    }
}

// MARK: - Controls

public struct TextField: View, PrimitiveView {
    let placeholder: String
    let text: Binding<String>
    public init(_ placeholder: String, text: Binding<String>) { self.placeholder = placeholder; self.text = text }
    public var body: Never { fatalError() }
    func makeNode() -> Node { TextFieldNode(placeholder: placeholder, text: text) }
}

public typealias SecureField = TextField

public struct Toggle<Label: View>: View, PrimitiveView {
    let label: Label
    let isOn: Binding<Bool>
    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) { self.isOn = isOn; self.label = label() }
    public var body: Never { fatalError() }
    func makeNode() -> Node { ToggleNode(label: resolve(label), isOn: isOn) }
}

extension Toggle where Label == Text {
    public init(_ title: String, isOn: Binding<Bool>) { self.isOn = isOn; self.label = Text(title) }
}

public struct Label: View, PrimitiveView {
    let title: String
    let systemImage: String
    public init(_ title: String, systemImage: String) { self.title = title; self.systemImage = systemImage }
    public var body: Never { fatalError() }
    func makeNode() -> Node {
        StackNode(axis: .horizontal, spacing: 14, children: [
            resolve(Image(systemName: systemImage).foregroundStyle(.tint)),
            resolve(Text(title)),
        ])
    }
}

public struct Divider: View, PrimitiveView {
    public init() {}
    public var body: Never { fatalError() }
    func makeNode() -> Node { DividerNode() }
}

// MARK: - Shapes

extension Color: View, PrimitiveView {
    public var body: Never { fatalError() }
    func makeNode() -> Node { let n = ShapeNode(kind: .rect, color: self); n.explicitColor = true; return n }
}

public struct ShapeView: View, PrimitiveView {
    let kind: ShapeNode.Kind
    var color: Color? = nil
    public var body: Never { fatalError() }
    public func fill<S: ShapeStyle>(_ s: S) -> ShapeView { var v = self; v.color = s.resolvedColor; return v }
    public func foregroundStyle<S: ShapeStyle>(_ s: S) -> ShapeView { fill(s) }
    func makeNode() -> Node {
        let n = ShapeNode(kind: kind, color: color ?? .black)
        n.explicitColor = color != nil
        return n
    }
}

public func Rectangle() -> ShapeView { ShapeView(kind: .rect) }
public func RoundedRectangle(cornerRadius: Double) -> ShapeView { ShapeView(kind: .rounded(cornerRadius)) }
public func Circle() -> ShapeView { ShapeView(kind: .circle) }
public func Capsule() -> ShapeView { ShapeView(kind: .capsule) }

// MARK: - Layout modifiers

public struct Alignment {
    let h: HorizontalAlignment
    let v: VerticalAlignment
    public static let center = Alignment(h: .center, v: .center)
    public static let leading = Alignment(h: .leading, v: .center)
    public static let trailing = Alignment(h: .trailing, v: .center)
    public static let top = Alignment(h: .center, v: .top)
    public static let bottom = Alignment(h: .center, v: .bottom)
    public static let topLeading = Alignment(h: .leading, v: .top)
    public static let topTrailing = Alignment(h: .trailing, v: .top)
    public static let bottomLeading = Alignment(h: .leading, v: .bottom)
    public static let bottomTrailing = Alignment(h: .trailing, v: .bottom)
}

public enum Edge {
    public struct Set: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let top = Set(rawValue: 1)
        public static let leading = Set(rawValue: 2)
        public static let bottom = Set(rawValue: 4)
        public static let trailing = Set(rawValue: 8)
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]
        public static let all: Set = [.top, .leading, .bottom, .trailing]
    }
}

public enum TextAlignment { case leading, center, trailing }

public enum TextFieldStyleKind { case automatic, plain, roundedBorder }
extension TextFieldStyleKind {
    public static var roundedBorderStyle: TextFieldStyleKind { .roundedBorder }
}

public enum ListStyleKind { case automatic, plain, grouped, insetGrouped, inset, sidebar }
public enum TitleDisplayMode { case automatic, inline, large }

extension View {
    public func frame(width: Double? = nil, height: Double? = nil, alignment: Alignment = .center) -> ModifiedView {
        let v = self
        return ModifiedView { FrameNode(width: width, height: height, maxWidth: nil, maxHeight: nil, hAlign: alignment.h, vAlign: alignment.v, child: resolve(v)) }
    }

    public func frame(minWidth: Double? = nil, maxWidth: Double? = nil, minHeight: Double? = nil, maxHeight: Double? = nil,
                      alignment: Alignment = .center) -> ModifiedView {
        let v = self
        return ModifiedView { FrameNode(width: nil, height: nil, maxWidth: maxWidth, maxHeight: maxHeight, hAlign: alignment.h, vAlign: alignment.v, child: resolve(v)) }
    }

    public func padding(_ edges: Edge.Set, _ length: Double = 16) -> ModifiedView {
        let v = self
        return ModifiedView {
            PaddingNode(top: edges.contains(.top) ? length : 0, leading: edges.contains(.leading) ? length : 0,
                        bottom: edges.contains(.bottom) ? length : 0, trailing: edges.contains(.trailing) ? length : 0,
                        child: resolve(v))
        }
    }

    public func navigationTitle(_ title: String) -> ModifiedView {
        let v = self
        return ModifiedView { NavTitleNode(title: title, child: resolve(v)) }
    }

    public func navigationBarTitleDisplayMode(_ mode: TitleDisplayMode) -> ModifiedView {
        let v = self
        return ModifiedView { resolve(v) }
    }

    public func listStyle(_ style: ListStyleKind) -> ModifiedView {
        let v = self
        return ModifiedView { resolve(v) }
    }

    public func textFieldStyle(_ style: TextFieldStyleKind) -> ModifiedView {
        let v = self
        return ModifiedView {
            let n = resolve(v)
            func walk(_ n: Node) {
                if let f = n as? TextFieldNode { f.rounded = style == .roundedBorder }
                n.children.forEach(walk)
            }
            walk(n)
            return n
        }
    }

    public func multilineTextAlignment(_ a: TextAlignment) -> ModifiedView {
        let v = self
        return ModifiedView {
            let n = resolve(v)
            func walk(_ n: Node) {
                if let t = n as? TextNode { t.centered = a == .center }
                n.children.forEach(walk)
            }
            walk(n)
            return n
        }
    }

    public func fontWeight(_ w: Font.Weight) -> ModifiedView {
        let v = self
        return ModifiedView {
            let n = resolve(v)
            func walk(_ n: Node) {
                if let t = n as? TextNode, t.face == "Segoe UI" { t.weight = w.value }
                n.children.forEach(walk)
            }
            walk(n)
            return n
        }
    }

    public func clipShape(_ shape: ShapeView) -> ModifiedView {
        let v = self
        return ModifiedView {
            let n = resolve(v)
            if case .rounded(let r) = shape.kind, let b = n as? BackgroundNode { b.radius = r }
            return n
        }
    }

    public func onAppear(perform action: (() -> Void)? = nil) -> ModifiedView {
        let v = self
        return ModifiedView { resolve(v) }
    }

    public func tint(_ color: Color) -> ModifiedView {
        let v = self
        return ModifiedView { let n = resolve(v); applyForeground(n, color); return n }
    }
}

extension Font {
    public struct Weight {
        let value: Int
        public static let ultraLight = Weight(value: 200)
        public static let thin = Weight(value: 250)
        public static let light = Weight(value: 300)
        public static let regular = Weight(value: 400)
        public static let medium = Weight(value: 500)
        public static let semibold = Weight(value: 600)
        public static let bold = Weight(value: 700)
        public static let heavy = Weight(value: 800)
        public static let black = Weight(value: 900)
    }
    public static func system(size: Double, weight: Weight) -> Font { Font(size: size, weight: weight.value) }
    public static let subheadline = Font(size: 15, weight: 400)
    public static let footnote = Font(size: 13, weight: 400)
    public static let caption2 = Font(size: 11, weight: 400)
}

extension Binding {
    public var projectedValue: Binding<Value> { self }
    public static func constant(_ value: Value) -> Binding<Value> { Binding(get: { value }, set: { _ in }) }
}
