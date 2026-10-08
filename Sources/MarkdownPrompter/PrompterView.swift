import AppKit
import SwiftUI
import PrompterCore

final class ScriptLayout {
    let storage = NSTextStorage()
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: .zero)
    var height = 0.0
    var headings: [(title: String, y: Double)] = []
    var textWidth = 700.0
    private var headingOffsets: [(String, Int)] = []
    private var cachedBlocks: [ScriptBlock] = []
    private var cachedStyle = ""
    private var cachedSize = CGSize.zero
    init() { container.lineFragmentPadding = 0; manager.addTextContainer(container); storage.addLayoutManager(manager) }
    func build(blocks: [ScriptBlock], settings: Settings, size: CGSize) {
        let style = "\(settings.fontName)|\(settings.fontSize)|\(settings.lineSpacing)|\(settings.margin)|\(settings.foreground)"
        guard blocks != cachedBlocks || style != cachedStyle || size != cachedSize else { return }
        cachedBlocks = blocks; cachedStyle = style; cachedSize = size
        textWidth = max(120, size.width * (1 - settings.margin * 2))
        container.size = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        let result = NSMutableAttributedString(string: ""); headingOffsets = []
        for block in blocks {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = settings.fontSize * (settings.lineSpacing - 1)
            paragraph.paragraphSpacing = settings.fontSize * 0.6
            var weight = NSFont.Weight.regular
            var scale = 1.0
            if case .heading(let level) = block.kind { weight = .bold; scale = level == 1 ? 1.15 : 1; headingOffsets.append((block.text, result.length)) }
            let base = FontCatalog.font(family: settings.fontName, size: settings.fontSize * scale)
            let font = weight == .bold ? NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) : base
            let text: NSMutableAttributedString
            if case .code = block.kind { text = NSMutableAttributedString(string: block.text) }
            else if let inline = try? AttributedString(markdown: block.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                text = NSMutableAttributedString(string: "")
                for run in inline.runs {
                    let s = String(inline[run.range].characters)
                    var f = font
                    if let intent = run.inlinePresentationIntent {
                        if intent.contains(.stronglyEmphasized) { f = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) }
                        if intent.contains(.emphasized) { f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) }
                        if intent.contains(.code) { f = NSFont.monospacedSystemFont(ofSize: settings.fontSize * 0.9, weight: .regular) }
                    }
                    text.append(NSAttributedString(string: s, attributes: [.font: f]))
                }
            } else { text = NSMutableAttributedString(string: block.text) }
            if case .bullet = block.kind { text.insert(NSAttributedString(string: "• ", attributes: [.font: font]), at: 0) }
            let range = NSRange(location: 0, length: text.length)
            text.enumerateAttribute(.font, in: range) { value, subrange, _ in if value == nil { text.addAttribute(.font, value: font, range: subrange) } }
            text.addAttributes([.foregroundColor: settings.foreground.ns, .paragraphStyle: paragraph], range: range)
            text.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: paragraph]))
            result.append(text)
        }
        storage.setAttributedString(result)
        manager.ensureLayout(for: container)
        height = manager.usedRect(for: container).height
        headings = headingOffsets.map { ($0.0, yForCharacter($0.1)) }
    }
    func yForCharacter(_ offset: Int) -> Double {
        guard storage.length > 0 else { return 0 }
        let glyph = manager.glyphIndexForCharacter(at: min(offset, storage.length - 1))
        return manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
    }
}

struct PrompterPreview: NSViewRepresentable {
    let model: AppModel
    func makeNSView(context: Context) -> PrompterCanvas { PrompterCanvas(model: model, interactive: true) }
    func updateNSView(_ view: PrompterCanvas, context: Context) { view.needsDisplay = true }
}

final class PrompterCanvas: NSView {
    let model: AppModel
    let interactive: Bool
    private var refresh: Timer?
    private var previousPosition = -1.0
    private var previousSettings: Settings?
    private var previousSize = CGSize.zero
    private var previousSource = ""
    private var previousBlanked = false
    private var previousCount = -1
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { interactive }
    init(model: AppModel, interactive: Bool) {
        self.model = model; self.interactive = interactive
        super.init(frame: .zero)
        wantsLayer = true
        refresh = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let m = self.model
            if self.previousSettings != m.settings || self.previousSize != m.canvasSize || self.previousSource != m.source {
                m.rebuildLayout(); self.previousSettings = m.settings; self.previousSize = m.canvasSize; self.previousSource = m.source; self.needsDisplay = true
            }
            if self.previousPosition != m.position || self.previousBlanked != m.blanked || self.previousCount != m.countdownRemaining {
                self.previousPosition = m.position; self.previousBlanked = m.blanked; self.previousCount = m.countdownRemaining; self.needsDisplay = true
            }
        }
        RunLoop.main.add(refresh!, forMode: .common)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { refresh?.invalidate() }
    var contentRect: NSRect {
        let size = model.canvasSize
        let scale = min(bounds.width / max(1, size.width), bounds.height / max(1, size.height))
        return NSRect(x: (bounds.width - size.width * scale) / 2, y: (bounds.height - size.height * scale) / 2, width: size.width * scale, height: size.height * scale)
    }
    override func draw(_ dirtyRect: NSRect) {
        // The output letterboxes to black; the preview is already sized to the display's aspect ratio.
        if !interactive { NSColor(calibratedWhite: 0.035, alpha: 1).setFill(); bounds.fill() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = contentRect; let size = model.canvasSize; let s = model.settings
        ctx.saveGState(); ctx.translateBy(x: r.minX, y: r.minY); ctx.scaleBy(x: r.width / size.width, y: r.height / size.height)
        let canvas = NSRect(origin: .zero, size: size)
        ctx.clip(to: canvas); s.background.ns.setFill(); canvas.fill()
        if model.blanked { ctx.restoreGState(); return }
        ctx.saveGState()
        if s.upsideDown { ctx.translateBy(x: size.width, y: size.height); ctx.rotate(by: .pi) }
        if s.mirror { ctx.translateBy(x: size.width, y: 0); ctx.scaleBy(x: -1, y: 1) }
        let band = ReadingBand(displayHeight: size.height, position: s.readingPosition, fontSize: s.fontSize, lineSpacing: s.lineSpacing, lines: s.readingLines)
        let origin = NSPoint(x: (size.width - model.layout.textWidth) / 2, y: band.textTop - model.position)
        let visible = NSRect(x: 0, y: max(0, -origin.y), width: model.layout.textWidth, height: size.height + s.fontSize * 3)
        let glyphs = model.layout.manager.glyphRange(forBoundingRect: visible, in: model.layout.container)
        model.layout.manager.drawGlyphs(forGlyphRange: glyphs, at: origin)
        if s.highlight {
            s.background.ns.withAlphaComponent(s.readingDimOpacity).setFill()
            NSRect(x: 0, y: 0, width: size.width, height: max(0, band.top)).fill()
            NSRect(x: 0, y: band.bottom, width: size.width, height: max(0, size.height - band.bottom)).fill()
        }
        ctx.restoreGState()
        // Camera marker uses physical screen coordinates, independent of text mirroring.
        if s.markerEnabled { drawMarker(at: NSPoint(x: size.width * s.markerX, y: size.height * s.markerY), size: s.markerSize, style: s.markerStyle, color: s.markerColor.ns, canvas: canvas) }
        if s.dimming < 1 { NSColor.black.withAlphaComponent(1 - s.dimming).setFill(); canvas.fill() }
        if model.countdownRemaining > 0 {
            NSColor.black.withAlphaComponent(0.65).setFill(); canvas.fill()
            let label = NSAttributedString(string: "\(model.countdownRemaining)", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 110, weight: .medium), .foregroundColor: NSColor.white])
            label.draw(at: NSPoint(x: (size.width - label.size().width) / 2, y: (size.height - label.size().height) / 2))
        }
        ctx.restoreGState()
    }
    private func drawMarker(at p: NSPoint, size: Double, style: MarkerStyle, color: NSColor, canvas: NSRect) {
        color.setStroke(); color.setFill()
        let path = NSBezierPath(); path.lineWidth = 2
        func line(_ a: NSPoint, _ b: NSPoint) { path.move(to: a); path.line(to: b) }
        switch style {
        case .dot: NSBezierPath(ovalIn: NSRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)).fill()
        case .line: line(NSPoint(x: 0, y: p.y), NSPoint(x: canvas.width, y: p.y))
        case .cross:
            line(NSPoint(x: p.x - size, y: p.y), NSPoint(x: p.x - 6, y: p.y)); line(NSPoint(x: p.x + 6, y: p.y), NSPoint(x: p.x + size, y: p.y))
            line(NSPoint(x: p.x, y: p.y - size), NSPoint(x: p.x, y: p.y - 6)); line(NSPoint(x: p.x, y: p.y + 6), NSPoint(x: p.x, y: p.y + size))
        case .brackets:
            for x in [-1.0, 1.0] { for y in [-1.0, 1.0] {
                let corner = NSPoint(x: p.x + x * size / 2, y: p.y + y * size / 2)
                line(NSPoint(x: corner.x - x * size * 0.28, y: corner.y), corner)
                line(corner, NSPoint(x: corner.x, y: corner.y - y * size * 0.28))
            } }
        }
        path.stroke()
    }
    override func resetCursorRects() { if interactive { addCursorRect(contentRect, cursor: .crosshair) } }
    override func mouseDown(with event: NSEvent) { moveMarker(event) }
    override func mouseDragged(with event: NSEvent) { moveMarker(event) }
    private func moveMarker(_ event: NSEvent) {
        guard interactive else { return }
        let p = convert(event.locationInWindow, from: nil); let r = contentRect
        guard r.contains(p) else { return }
        model.settings.markerX = min(1, max(0, (p.x - r.minX) / r.width))
        model.settings.markerY = min(1, max(0, (p.y - r.minY) / r.height))
    }
    override func scrollWheel(with event: NSEvent) { if interactive { model.nudge(-event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 12)) } }
}

final class ProjectionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class OutputController {
    unowned let model: AppModel
    private var panel: ProjectionPanel?
    private lazy var escapeShortcut = ProjectionEscapeShortcut(
        onEscape: { [weak self] in self?.model.stopProjection() },
        onFailure: { [weak self] in self?.model.error = "Couldn’t enable Escape to stop projection. Use Control–Option–Command–P or Stop Projection in Cue’s menu bar." }
    )
    init(model: AppModel) { self.model = model }
    func show() {
        guard let screen = model.selectedScreen else { return }
        if panel == nil {
            let p = ProjectionPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.title = "Cue — Prompter Output"; p.isReleasedWhenClosed = false; p.backgroundColor = .black
            p.level = .screenSaver; p.hidesOnDeactivate = false; p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.contentView = PrompterCanvas(model: model, interactive: false); panel = p
        }
        panel?.setFrame(screen.frame, display: true); panel?.orderFrontRegardless()
        escapeShortcut.start(frame: screen.frame)
    }
    func hide() { escapeShortcut.stop(); panel?.orderOut(nil); panel = nil }
}
