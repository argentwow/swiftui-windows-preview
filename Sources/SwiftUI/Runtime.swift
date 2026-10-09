// Windows host for the view tree: a Win32 window drawn with GDI.
import WinSDK

final class Graphics {
    let hdc: HDC
    let scale: Double
    private var fonts: [String: HFONT] = [:]

    init(hdc: HDC, scale: Double) { self.hdc = hdc; self.scale = scale }

    deinit { fonts.values.forEach { DeleteObject($0) } }

    private func font(size: Double, weight: Int, face: String = "Segoe UI") -> HFONT {
        let key = "\(size)-\(weight)-\(face)"
        if let f = fonts[key] { return f }
        // iOS system font: SF Pro Text below 20pt, SF Pro Display from 20pt (when the user supplied them)
        var actual = face
        if face == "Segoe UI" && Runtime.hasSFPro { actual = size >= 20 ? "SF Pro Display" : "SF Pro Text" }
        // Supersampled frames are downscaled smoothly, so use grayscale AA (ClearType would fringe)
        let quality = Runtime.supersample > 1 ? DWORD(ANTIALIASED_QUALITY) : DWORD(CLEARTYPE_QUALITY)
        let f = actual.withCString(encodedAs: UTF16.self) { name in
            CreateFontW(Int32(-size * scale), 0, 0, 0, Int32(weight), 0, 0, 0,
                        DWORD(DEFAULT_CHARSET), DWORD(OUT_DEFAULT_PRECIS), DWORD(CLIP_DEFAULT_PRECIS),
                        quality, DWORD(DEFAULT_PITCH), name)
        }!
        fonts[key] = f
        return f
    }

    func measureText(_ text: String, size: Double, weight: Int, face: String = "Segoe UI") -> Size {
        SelectObject(hdc, font(size: size, weight: weight, face: face))
        let u = Array(text.utf16)
        var s = SIZE()
        GetTextExtentPoint32W(hdc, u, Int32(u.count), &s)
        return Size(w: Double(s.cx) / scale, h: Double(s.cy) / scale)
    }

    func drawText(_ text: String, x: Double, y: Double, size: Double, weight: Int, color: Color, face: String = "Segoe UI") {
        SelectObject(hdc, font(size: size, weight: weight, face: face))
        SetBkMode(hdc, TRANSPARENT)
        SetTextColor(hdc, rgb(color))
        let u = Array(text.utf16)
        TextOutW(hdc, Int32(x * scale), Int32(y * scale), u, Int32(u.count))
    }

    private let wrapFlags = UINT(DT_WORDBREAK) | UINT(DT_NOPREFIX)

    func measureWrapped(_ text: String, width: Double, size: Double, weight: Int, face: String = "Segoe UI") -> Size {
        SelectObject(hdc, font(size: size, weight: weight, face: face))
        var u = Array(text.utf16)
        var rc = RECT(left: 0, top: 0, right: Int32(width * scale), bottom: 0)
        DrawTextW(hdc, &u, Int32(u.count), &rc, wrapFlags | UINT(DT_CALCRECT))
        return Size(w: Double(rc.right) / scale, h: Double(rc.bottom) / scale)
    }

    func drawWrapped(_ text: String, in r: Rect, size: Double, weight: Int, color: Color, face: String = "Segoe UI", centered: Bool = false) {
        SelectObject(hdc, font(size: size, weight: weight, face: face))
        SetBkMode(hdc, TRANSPARENT)
        SetTextColor(hdc, rgb(color))
        var u = Array(text.utf16)
        var rc = RECT(left: Int32(r.x * scale), top: Int32(r.y * scale),
                      right: Int32((r.x + r.w) * scale) + 2, bottom: Int32((r.y + r.h) * scale) + 2)
        DrawTextW(hdc, &u, Int32(u.count), &rc, wrapFlags | (centered ? UINT(DT_CENTER) : 0))
    }

    func fillEllipse(_ r: Rect, color: Color) {
        let brush = CreateSolidBrush(rgb(color))
        let oldBrush = SelectObject(hdc, brush)
        let oldPen = SelectObject(hdc, GetStockObject(NULL_PEN))
        Ellipse(hdc, Int32(r.x * scale), Int32(r.y * scale), Int32((r.x + r.w) * scale) + 1, Int32((r.y + r.h) * scale) + 1)
        SelectObject(hdc, oldPen)
        SelectObject(hdc, oldBrush)
        DeleteObject(brush)
    }

    func strokeRoundRect(_ r: Rect, radius: Double, color: Color) {
        let pen = CreatePen(PS_SOLID, Int32(max(1, scale)), rgb(color))
        let oldPen = SelectObject(hdc, pen)
        let oldBrush = SelectObject(hdc, GetStockObject(NULL_BRUSH))
        RoundRect(hdc, Int32(r.x * scale), Int32(r.y * scale),
                  Int32((r.x + r.w) * scale), Int32((r.y + r.h) * scale),
                  Int32(radius * 2 * scale), Int32(radius * 2 * scale))
        SelectObject(hdc, oldBrush)
        SelectObject(hdc, oldPen)
        DeleteObject(pen)
    }

    /// Restrict drawing to `r` until the matching popClip().
    func pushClip(_ r: Rect) {
        SaveDC(hdc)
        IntersectClipRect(hdc, Int32(r.x * scale), Int32(r.y * scale), Int32((r.x + r.w) * scale), Int32((r.y + r.h) * scale))
    }

    func popClip() { RestoreDC(hdc, -1) }

    func fillRoundRect(_ r: Rect, radius: Double, color: Color) {
        let brush = CreateSolidBrush(rgb(color))
        let oldBrush = SelectObject(hdc, brush)
        let oldPen = SelectObject(hdc, GetStockObject(NULL_PEN))
        // Hairlines (separators) must stay at least one device pixel tall/wide
        let x0 = Int32(r.x * scale), y0 = Int32(r.y * scale)
        let x1 = max(x0 + 1, Int32((r.x + r.w) * scale)), y1 = max(y0 + 1, Int32((r.y + r.h) * scale))
        RoundRect(hdc, x0, y0, x1 + 1, y1 + 1, Int32(radius * 2 * scale), Int32(radius * 2 * scale))
        SelectObject(hdc, oldPen)
        SelectObject(hdc, oldBrush)
        DeleteObject(brush)
    }

    /// One window-pixel horizontal line snapped to the pixel grid (list separators).
    func hairline(x: Double, y: Double, w: Double, color: Color) {
        let ss = Double(Runtime.supersample)
        let windowScale = scale / ss
        let py = (y * windowScale).rounded(.down) * ss          // top of that window pixel, in buffer pixels
        let brush = CreateSolidBrush(rgb(color))
        var rc = RECT(left: Int32(x * scale), top: Int32(py), right: Int32((x + w) * scale), bottom: Int32(py + ss))
        FillRect(hdc, &rc, brush)
        DeleteObject(brush)
    }

    /// Clip to a rounded rectangle (the phone screen's corners).
    func pushRoundClip(_ r: Rect, radius: Double) {
        SaveDC(hdc)
        let rgn = CreateRoundRectRgn(Int32(r.x * scale), Int32(r.y * scale), Int32((r.x + r.w) * scale) + 1,
                                     Int32((r.y + r.h) * scale) + 1, Int32(radius * 2 * scale), Int32(radius * 2 * scale))
        ExtSelectClipRgn(hdc, rgn, RGN_AND)
        DeleteObject(rgn)
    }

    private func rgb(_ c: Color) -> COLORREF {
        COLORREF(c.r) | (COLORREF(c.g) << 8) | (COLORREF(c.b) << 16)
    }
}

public enum Runtime {
    // @State storage (see State). Positional slots, one namespace per navigation depth
    // so pushing a page doesn't shift the slots of the pages below it.
    static var stateSpaces: [Int: [AnyObject]] = [:]
    static var stateCursors: [Int: Int] = [:]
    static var stateNamespace = 0
    static var stateCursor: Int {
        get { 0 }
        set { stateCursors = [:]; stateNamespace = 0 }   // "stateCursor = 0" resets a render pass
    }

    static func stateSlot<T: AnyObject>(_ make: () -> T) -> T {
        let ns = stateNamespace
        var slots = stateSpaces[ns] ?? []
        let i = stateCursors[ns] ?? 0
        stateCursors[ns] = i + 1
        if i < slots.count, let existing = slots[i] as? T { return existing }
        let b = make()
        if i < slots.count { slots[i] = b } else { slots.append(b) }
        stateSpaces[ns] = slots
        return b
    }

    static var hwnd: HWND?
    static var makeContent: (() -> any View)?
    static var root: Node?
    static var buttons: [TapNode] = []
    static var screenBackground = Color.white
    static var hoverIndex: Int?
    static var pressIndex: Int?
    static var scale = 1.0

    // Preview mode: iPhone frame, iOS styling, always-on-top window
    static var iOSStyle = false
    static var preview = false
    static let device = Size(w: 402, h: 874)      // iPhone 17 Pro points
    static let bezel = 12.0, margin = 20.0
    static var zoom = 0.85
    static var posFile: String? = nil

    static func invalidate() {
        if let hwnd { InvalidateRect(hwnd, nil, false) }
    }

    /// Re-evaluate body from the root and lay it out centered in the client area.
    static func rebuild(_ g: Graphics, x: Double = 0, y: Double = 0, width: Double, height: Double) {
        stateCursor = 0
        screenBackground = .white
        beginPass()
        let node = resolve(makeContent!())
        scrollNodes = []
        collectScrolls(node)
        let s = node.sizeThatFits(Proposal(w: width, h: height), g)
        let w = min(s.w, width), h = min(s.h, height)
        node.place(Rect(x: x + (width - w) / 2, y: y + (height - h) / 2, w: w, h: h), g)
        root = node
        var bs: [TapNode] = []
        collectTargets(node, clip: Rect(x: x, y: y, w: width, h: height), into: &bs)
        for (i, b) in bs.enumerated() {
            b.hovered = i == hoverIndex
            b.pressed = i == pressIndex
        }
        buttons = bs
    }

    /// Clickable nodes in tree order; each remembers the visible area it lives in.
    static func collectTargets(_ n: Node, clip: Rect, into out: inout [TapNode]) {
        var clip = clip
        if let c = n as? ClippingNode { clip = clip.intersection(c.clipRect) }
        if let t = n as? TapNode { t.clip = clip; out.append(t) }
        n.children.forEach { collectTargets($0, clip: clip, into: &out) }
    }

    static func point(_ lParam: LPARAM) -> (Double, Double) {
        (Double(Int16(truncatingIfNeeded: lParam & 0xFFFF)) / scale,
         Double(Int16(truncatingIfNeeded: (lParam >> 16) & 0xFFFF)) / scale)
    }

    /// Innermost (last in tree order) target under the point, respecting clipping.
    static func buttonIndex(at lParam: LPARAM) -> Int? {
        let (x, y) = point(lParam)
        return buttons.lastIndex { $0.frame.contains(x, y) && ($0.clip?.contains(x, y) ?? true) }
    }

    static func paint(_ hwnd: HWND) {
        var ps = PAINTSTRUCT()
        guard let hdc = BeginPaint(hwnd, &ps) else { return }
        var rc = RECT()
        GetClientRect(hwnd, &rc)
        let w = rc.right - rc.left, h = rc.bottom - rc.top

        // Double buffer to avoid flicker. GDI shapes have no anti-aliasing, so the preview
        // renders at `supersample`x and is smoothly downscaled (HALFTONE) onto the window.
        let ss = Int32(supersample)
        let mem = CreateCompatibleDC(hdc)!
        let bmp = CreateCompatibleBitmap(hdc, w * ss, h * ss)!
        let oldBmp = SelectObject(mem, bmp)
        let desk: UInt8 = preview ? 226 : 236
        let bg = CreateSolidBrush(COLORREF(desk) | (COLORREF(desk) << 8) | (COLORREF(desk) << 16))
        var big = RECT(left: 0, top: 0, right: w * ss, bottom: h * ss)
        FillRect(mem, &big, bg)
        DeleteObject(bg)

        let g = Graphics(hdc: mem, scale: scale * Double(ss))
        if preview {
            // Device body, screen, Dynamic Island, status bar
            let body = Rect(x: margin, y: margin, w: device.w + bezel * 2, h: device.h + bezel * 2)
            g.fillRoundRect(body, radius: 62, color: Color(24, 24, 26))
            let screen = Rect(x: margin + bezel, y: margin + bezel, w: device.w, h: device.h)
            // Content area = screen minus top safe area (62) and home indicator (34).
            // Layout first: a List/NavigationStack may change the screen background.
            rebuild(g, x: screen.x, y: screen.y + 62, width: device.w, height: device.h - 62 - 34)
            g.fillRoundRect(screen, radius: 52, color: screenBackground)
            g.pushRoundClip(screen, radius: 52)
            root?.draw(g)
            g.popClip()
            g.fillRoundRect(Rect(x: screen.x + (device.w - 124) / 2, y: screen.y + 11, w: 124, h: 36), radius: 18, color: .black)
            g.drawText("9:41", x: screen.x + 50, y: screen.y + 17, size: 17, weight: 600, color: .black)
            g.fillRoundRect(Rect(x: screen.x + (device.w - 140) / 2, y: screen.y + device.h - 13, w: 140, h: 5), radius: 2.5, color: .black)
        } else {
            rebuild(g, width: Double(w) / scale, height: Double(h) / scale)
            root?.draw(g)
        }

        if ss > 1 {
            SetStretchBltMode(hdc, HALFTONE)
            SetBrushOrgEx(hdc, 0, 0, nil)
            StretchBlt(hdc, 0, 0, w, h, mem, 0, 0, w * ss, h * ss, DWORD(SRCCOPY))
        } else {
            BitBlt(hdc, 0, 0, w, h, mem, 0, 0, DWORD(SRCCOPY))
        }
        SelectObject(mem, oldBmp)
        DeleteObject(bmp)
        DeleteDC(mem)
        EndPaint(hwnd, &ps)
    }

    static let wndProc: WNDPROC = { hwnd, msg, wParam, lParam in
        switch Int32(msg) {
        case WM_PAINT:
            Runtime.paint(hwnd!)
            return 0
        case WM_ERASEBKGND:
            return 1
        case WM_MOUSEMOVE:
            let (x, y) = Runtime.point(lParam)
            // Drag-to-scroll, like a finger on the phone
            if let d = Runtime.drag {
                if !Runtime.dragging && abs(y - d.startY) > 6 {
                    Runtime.dragging = true
                    Runtime.pressIndex = nil
                }
                if Runtime.dragging, let s = Runtime.scrollNodes.first(where: { $0.id == d.scrollID }) {
                    s.offset = d.startOffset - (y - d.startY)
                    Runtime.scrolling = s.id
                    Runtime.invalidate()
                }
                return 0
            }
            let i = Runtime.buttonIndex(at: lParam)
            if i != Runtime.hoverIndex { Runtime.hoverIndex = i; Runtime.invalidate() }
            let hand = i.map { Runtime.buttons[$0].cursorHand } ?? false
            let beam = i.map { Runtime.buttons[$0] is TextFieldNode } ?? false
            SetCursor(LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: beam ? 32513 : hand ? 32649 : 32512)))
            return 0
        case WM_LBUTTONDOWN:
            let (x, y) = Runtime.point(lParam)
            Runtime.pressIndex = Runtime.buttonIndex(at: lParam)
            if let s = Runtime.scrollNode(atX: x, y: y) {
                Runtime.drag = (s.id, y, s.offset)
            }
            SetCapture(hwnd)
            Runtime.invalidate()
            return 0
        case WM_LBUTTONUP:
            ReleaseCapture()
            let wasDragging = Runtime.dragging
            Runtime.drag = nil
            Runtime.dragging = false
            Runtime.scrolling = nil
            let i = Runtime.buttonIndex(at: lParam)
            let pressed = Runtime.pressIndex
            Runtime.pressIndex = nil
            if !wasDragging {
                if let i, i == pressed, i < Runtime.buttons.count {
                    let target = Runtime.buttons[i]
                    if !(target is TextFieldNode) { Runtime.focusedField = nil }
                    let (x, y) = Runtime.point(lParam)
                    target.tap(x: x, y: y)
                } else {
                    Runtime.focusedField = nil
                }
            }
            Runtime.invalidate()
            return 0
        case WM_MOUSEWHEEL:
            var pt = POINT(x: Int32(Int16(truncatingIfNeeded: lParam & 0xFFFF)), y: Int32(Int16(truncatingIfNeeded: (lParam >> 16) & 0xFFFF)))
            ScreenToClient(hwnd, &pt)
            let delta = Double(Int16(truncatingIfNeeded: (wParam >> 16) & 0xFFFF)) / 120
            if let s = Runtime.scrollNode(atX: Double(pt.x) / Runtime.scale, y: Double(pt.y) / Runtime.scale) {
                s.offset -= delta * 60
                Runtime.scrolling = s.id
                Runtime.invalidate()
                SetTimer(hwnd, 2, 700, nil)   // hide the indicator shortly after
            }
            return 0
        case WM_CHAR:
            if let id = Runtime.focusedField,
               let f = Runtime.buttons.first(where: { ($0 as? TextFieldNode)?.id == id }) as? TextFieldNode {
                f.key(UInt16(truncatingIfNeeded: wParam))
                Runtime.caretOn = true
                Runtime.invalidate()
            }
            return 0
        case WM_TIMER:
            if wParam == 1, Runtime.focusedField != nil {
                Runtime.caretOn.toggle()
                Runtime.invalidate()
            } else if wParam == 2 {
                KillTimer(hwnd, 2)
                if Runtime.drag == nil { Runtime.scrolling = nil; Runtime.invalidate() }
            }
            return 0
        case WM_MOVE:
            if let path = Runtime.posFile {
                var r = RECT()
                GetWindowRect(hwnd, &r)
                Runtime.writeFile(path, "\(r.left) \(r.top)")
            }
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        case WM_DESTROY:
            PostQuitMessage(0)
            return 0
        default:
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        }
    }

    static func run(title: String, content: @escaping () -> any View) {
        makeContent = content
        SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
        scale = Double(GetDpiForSystem()) / 96.0 * (preview ? zoom : 1.0)

        let hInstance = GetModuleHandleW(nil)
        let className = Array("SwiftUIWindow".utf16) + [0]
        className.withUnsafeBufferPointer { cls in
            var wc = WNDCLASSEXW()
            wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            wc.style = UINT(CS_HREDRAW | CS_VREDRAW)
            wc.lpfnWndProc = wndProc
            wc.hInstance = hInstance
            wc.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
            wc.lpszClassName = cls.baseAddress
            RegisterClassExW(&wc)
        }

        // Size the window to fit the content (measured with a screen DC)
        let screen = GetDC(nil)!
        let g = Graphics(hdc: screen, scale: scale)
        stateCursor = 0
        let s = resolve(content()).sizeThatFits(.ideal, g)
        ReleaseDC(nil, screen)
        stateCursor = 0

        var rc = preview
            ? RECT(left: 0, top: 0,
                   right: Int32((device.w + (bezel + margin) * 2) * scale), bottom: Int32((device.h + (bezel + margin) * 2) * scale))
            : RECT(left: 0, top: 0,
                   right: Int32(max(420, s.w + 80) * scale), bottom: Int32(max(300, s.h + 80) * scale))
        AdjustWindowRectExForDpi(&rc, DWORD(WS_OVERLAPPEDWINDOW), false, 0, GetDpiForSystem())

        let titleW = Array(title.utf16) + [0]
        hwnd = CreateWindowExW(0, className, titleW, DWORD(WS_OVERLAPPEDWINDOW),
                               Int32(bitPattern: 0x80000000), 0,
                               rc.right - rc.left, rc.bottom - rc.top,
                               nil, nil, hInstance, nil)
        if preview {
            var x = Int32(bitPattern: 0x80000000), y: Int32 = 0
            if let path = posFile, let saved = readFile(path) {
                let parts = saved.split(separator: " ").compactMap { Int32($0) }
                if parts.count == 2 { x = parts[0]; y = parts[1] }
            }
            let flags = UINT(SWP_NOSIZE) | (x == Int32(bitPattern: 0x80000000) ? UINT(SWP_NOMOVE) : 0)
            SetWindowPos(hwnd, HWND(bitPattern: -1), x, y, 0, 0, flags)   // HWND_TOPMOST
        }
        ShowWindow(hwnd, SW_SHOWNOACTIVATE)
        UpdateWindow(hwnd)
        SetTimer(hwnd, 1, 530, nil)   // text caret blink

        var msg = MSG()
        while GetMessageW(&msg, nil, 0, 0) {
            TranslateMessage(&msg)
            DispatchMessageW(&msg)
        }
    }
}


extension Runtime {
    /// Entry point used by the preview host.
    public static func runPreview(title: String, content: @escaping () -> any View) {
        preview = true
        iOSStyle = true
        supersample = 3
        hasSFPro = loadPrivateFonts(dir: "fonts")
        if let tmp = getenv("TEMP") { posFile = String(cString: tmp) + "/swiftui-preview-pos.txt" }
        run(title: title, content: content)
    }

    static func writeFile(_ path: String, _ text: String) {
        guard let f = fopen(path, "w") else { return }
        fputs(text, f)
        fclose(f)
    }

    static func readFile(_ path: String) -> String? {
        guard let f = fopen(path, "r") else { return nil }
        defer { fclose(f) }
        var buf = [CChar](repeating: 0, count: 64)
        guard fgets(&buf, 64, f) != nil else { return nil }
        return String(cString: buf)
    }
}

// MARK: - Fonts and render quality

extension Runtime {
    static var supersample = 1
    static var hasSFPro = false

    /// Load every .otf/.ttf in `dir` for this process only (FR_PRIVATE: nothing is installed system-wide).
    /// Returns true if the SF Pro families are available.
    static func loadPrivateFonts(dir: String) -> Bool {
        var found = false
        for pattern in ["\(dir)/*.otf", "\(dir)/*.ttf"] {
            var data = WIN32_FIND_DATAW()
            let h = pattern.withCString(encodedAs: UTF16.self) { FindFirstFileW($0, &data) }
            guard let h, h != INVALID_HANDLE_VALUE else { continue }
            repeat {
                let name = withUnsafeBytes(of: data.cFileName) { raw in
                    String(decoding: raw.bindMemory(to: UInt16.self).prefix { $0 != 0 }, as: UTF16.self)
                }
                let path = "\(dir)/\(name)"
                let added = path.withCString(encodedAs: UTF16.self) { AddFontResourceExW($0, DWORD(FR_PRIVATE), nil) }
                if added > 0 && name.hasPrefix("SF-Pro") { found = true }
            } while FindNextFileW(h, &data)
            FindClose(h)
        }
        return found
    }
}
