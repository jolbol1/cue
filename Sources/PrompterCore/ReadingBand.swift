import Foundation

/// The reading position is the centre of the focused band, in unrotated text coordinates.
public struct ReadingBand {
    public let centerY: Double
    public let height: Double
    public var top: Double { centerY - height / 2 }
    public var bottom: Double { centerY + height / 2 }
    public var textTop: Double { top + 6 }

    public init(displayHeight: Double, position: Double, fontSize: Double, lineSpacing: Double, lines: Double = 2) {
        centerY = displayHeight * position
        height = fontSize * (1 + lineSpacing) * 1.1 * lines / 2
    }

    public static func position(alignedTo markerY: Double, rotated: Bool) -> Double {
        rotated ? 1 - markerY : markerY
    }
}
