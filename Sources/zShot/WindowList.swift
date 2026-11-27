import CoreGraphics
import Foundation

enum WindowList {
    private static let minimumSide: CGFloat = 40

    /// Normal app windows other than zShot's, front to back, in global AppKit points.
    /// `primaryHeight` is the primary display's height, needed because Quartz window bounds are top-left based.
    static func snapshot(primaryHeight: CGFloat) -> [CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = Int(getpid())
        var rects: [CGRect] = []
        for window in info {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowOwnerPID as String] as? Int) != ownPID,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsInfo = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.width >= minimumSide, bounds.height >= minimumSide
            else { continue }
            rects.append(CGRect(x: bounds.minX, y: primaryHeight - bounds.minY - bounds.height, width: bounds.width, height: bounds.height))
        }
        return rects
    }
}
