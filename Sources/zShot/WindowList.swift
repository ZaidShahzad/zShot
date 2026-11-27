import CoreGraphics
import Foundation
import ZShotCore

enum WindowList {
    private static let minimumSide: CGFloat = 40

    /// On-screen windows other than zShot's, front to back, in global AppKit points. Normal app windows are targets.
    /// The Dock, the menu bar, and other windows above them are not, but still cover what is behind them.
    /// `primaryHeight` is the primary display's height, needed because Quartz window bounds are top-left based.
    static func snapshot(primaryHeight: CGFloat) -> [ScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = Int(getpid())
        var windows: [ScreenWindow] = []
        for window in info {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer >= 0,
                  (window[kCGWindowOwnerPID as String] as? Int) != ownPID,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsInfo = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary)
            else { continue }
            let frame = CGRect(x: bounds.minX, y: primaryHeight - bounds.minY - bounds.height, width: bounds.width, height: bounds.height)
            let isTarget = layer == 0 && bounds.width >= minimumSide && bounds.height >= minimumSide
            windows.append(ScreenWindow(id: id, frame: frame, isTarget: isTarget))
        }
        return windows
    }
}
