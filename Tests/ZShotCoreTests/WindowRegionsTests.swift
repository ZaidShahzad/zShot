import CoreGraphics
import Testing
import ZShotCore

private let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
private let front = CGRect(x: 100, y: 100, width: 300, height: 200)
private let back = CGRect(x: 50, y: 50, width: 800, height: 600)

private func area(_ rects: [CGRect]) -> CGFloat {
    rects.reduce(0) { $0 + $1.width * $1.height }
}

private func appWindow(_ frame: CGRect) -> ScreenWindow {
    ScreenWindow(id: 1, frame: frame, isTarget: true)
}

@Test func backWindowIsCoveredExactlyWhereTheFrontWindowIs() throws {
    let targets = WindowRegions.targets([appWindow(front), appWindow(back)], displays: [display])
    try #require(targets.count == 2)
    #expect(targets[0].frame == front)
    #expect(targets[0].covered.isEmpty)
    #expect(area(targets[0].visible) == area([front]))

    let backTarget = targets[1]
    #expect(backTarget.frame == back)
    #expect(backTarget.visible.allSatisfy { back.contains($0) && $0.intersection(front).isEmpty })
    #expect(area(backTarget.visible) == area([back]) - area([front]))
    #expect(backTarget.covered.allSatisfy { front.contains($0) })
    #expect(area(backTarget.covered) == area([front]))
}

@Test func nonTargetWindowsCoverWindowsWithoutBeingTargets() throws {
    let dock = CGRect(x: 0, y: 0, width: 1440, height: 70)
    let targets = WindowRegions.targets([ScreenWindow(id: 2, frame: dock, isTarget: false), appWindow(back)], displays: [display])
    try #require(targets.count == 1)
    #expect(targets[0].frame == back)
    #expect(targets[0].visible.allSatisfy { $0.intersection(dock).isEmpty })
    #expect(area(targets[0].visible) == area([back]) - 800 * 20)
}

@Test func nonTargetWindowSpanningADisplayCoversNothing() {
    let targets = WindowRegions.targets([ScreenWindow(id: 2, frame: display, isTarget: false), appWindow(front)], displays: [display])
    #expect(targets.map(\.frame) == [front])
    #expect(targets.map(\.covered) == [[]])
}

@Test func windowsHiddenBehindOthersAreDropped() {
    let targets = WindowRegions.targets([appWindow(back), appWindow(front)], displays: [display])
    #expect(targets.map(\.frame) == [back])
}

@Test func subtractWithoutOverlapKeepsTheRect() {
    #expect(WindowRegions.subtract(CGRect(x: 1000, y: 0, width: 10, height: 10), from: back) == [back])
}

@Test func subtractCoveringTheRectLeavesNothing() {
    #expect(WindowRegions.subtract(display, from: back).isEmpty)
}

@Test func subtractingAHoleLeavesFourDisjointPiecesAroundIt() {
    let pieces = WindowRegions.subtract(front, from: back)
    #expect(pieces.count == 4)
    #expect(area(pieces) == area([back]) - area([front]))
    #expect(pieces.allSatisfy { back.contains($0) && $0.intersection(front).isEmpty })
    for (index, piece) in pieces.enumerated() {
        for other in pieces[(index + 1)...] {
            #expect(piece.intersection(other).isEmpty)
        }
    }
}
