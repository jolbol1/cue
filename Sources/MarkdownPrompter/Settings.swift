import SwiftUI
import AppKit
import PrompterCore

struct RGBA: Codable, Equatable {
    var r: Double; var g: Double; var b: Double; var a: Double = 1
    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(nsColor: ns) }
    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(_ color: Color) { let c = NSColor(color).usingColorSpace(.sRGB) ?? .white; r = c.redComponent; g = c.greenComponent; b = c.blueComponent; a = c.alphaComponent }
}

enum ScrollMode: String, Codable, CaseIterable {
    case pedal = "Pedal", constant = "Constant"

    init(from decoder: Decoder) throws {
        let stored = try decoder.singleValueContainer().decode(String.self)
        // Retired modes fall back without discarding the user's other saved settings.
        self = Self(rawValue: stored) ?? .pedal
    }
}
enum MarkerStyle: String, Codable, CaseIterable { case cross = "Crosshair", brackets = "Brackets", dot = "Dot", line = "Reading line" }

struct Settings: Codable, Equatable {
    var fontName = "Helvetica Neue"
    var fontSize = 48.0
    var lineSpacing = 1.35
    var margin = 0.15
    var readingPosition = 0.38
    var foreground = RGBA(0.95, 0.96, 0.98)
    var background = RGBA(0.015, 0.02, 0.03)
    var mirror = false
    var upsideDown = false
    var dimming = 1.0
    var highlight = true
    // Optional storage lets settings saved by older builds decode without losing preferences.
    private var savedReadingLines: Double?
    private var savedReadingDimOpacity: Double?
    private var savedFileSortOrder: String?
    var fileSortOrder: FileSortOrder {
        get { savedFileSortOrder.flatMap(FileSortOrder.init(rawValue:)) ?? .nameAscending }
        set { savedFileSortOrder = newValue.rawValue }
    }
    var readingLines: Double {
        get { savedReadingLines ?? 2 }
        set { savedReadingLines = min(5, max(1, newValue)) }
    }
    var readingDimOpacity: Double {
        get { savedReadingDimOpacity ?? 0.62 }
        set { savedReadingDimOpacity = min(1, max(0, newValue)) }
    }
    var includeCode = false
    var markerEnabled = true
    var markerStyle = MarkerStyle.brackets
    var markerColor = RGBA(0.40, 0.83, 0.69, 0.8)
    var markerX = 0.5
    var markerY = 0.38
    var markerSize = 28.0
    var speed = 45.0
    var pedalSpeed = 90.0
    var mode = ScrollMode.pedal
    var loop = false
    var countdown = 3
    var displayID: UInt32 = 0
    var folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents").path
    var lastFile = ""
    var pedalEnabled = false
}
