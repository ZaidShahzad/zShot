import CoreGraphics
import Testing
import ZShotCore

private let origin = CGPoint(x: 100, y: 100)

private func isClose(_ a: CGPoint, _ b: CGPoint) -> Bool {
    abs(a.x - b.x) < 0.0001 && abs(a.y - b.y) < 0.0001
}

@Test func shiftSnapsLinesToNearest45DegreesKeepingLength() {
    let nearlyRight = Geometry.snapped45(from: origin, to: CGPoint(x: 200, y: 110))
    #expect(isClose(nearlyRight, CGPoint(x: 100 + (10_100.0).squareRoot(), y: 100)))

    let nearlyDiagonal = Geometry.snapped45(from: origin, to: CGPoint(x: 150, y: 140))
    let length = (50.0 * 50.0 + 40.0 * 40.0).squareRoot()
    let leg = length / 2.0.squareRoot()
    #expect(isClose(nearlyDiagonal, CGPoint(x: 100 + leg, y: 100 + leg)))

    let nearlyDown = Geometry.snapped45(from: origin, to: CGPoint(x: 95, y: 20))
    #expect(nearlyDown.x == 100)
}

@Test func shiftMakesSquaresFromTheLargerSideKeepingDirection() {
    #expect(Geometry.squared(from: origin, to: CGPoint(x: 150, y: 120)) == CGPoint(x: 150, y: 150))
    #expect(Geometry.squared(from: origin, to: CGPoint(x: 80, y: 30)) == CGPoint(x: 30, y: 30))
    #expect(Geometry.squared(from: origin, to: CGPoint(x: 130, y: 60)) == CGPoint(x: 140, y: 60))
}

@Test func constrainedShapes() {
    let end = CGPoint(x: 160, y: 120)
    #expect(Shape.make(tool: .circle, start: origin, end: end, constrained: true) == .ellipse(CGRect(x: 100, y: 100, width: 60, height: 60)))
    #expect(Shape.make(tool: .rectangle, start: origin, end: end, constrained: false) == .rectangle(CGRect(x: 100, y: 100, width: 60, height: 20)))
    #expect(Shape.make(tool: .line, start: origin, end: CGPoint(x: 100, y: 150), constrained: true) == .line(from: origin, to: CGPoint(x: 100, y: 150)))
}

@Test func historyUndoRedo() {
    let first = Annotation(shape: .line(from: .zero, to: origin), swatch: .red, thickness: .thin)
    let second = Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 5, height: 5)), swatch: .blue, thickness: .thick)
    var history = AnnotationHistory()
    #expect(history.undo() == false)
    history.add(first)
    history.add(second)
    #expect(history.undo())
    #expect(history.annotations == [first])
    #expect(history.redo())
    #expect(history.annotations == [first, second])
    #expect(history.redo() == false)
}

@Test func addingAfterUndoClearsRedo() {
    let first = Annotation(shape: .line(from: .zero, to: origin), swatch: .red, thickness: .thin)
    let second = Annotation(shape: .line(from: origin, to: .zero), swatch: .green, thickness: .thin)
    var history = AnnotationHistory()
    history.add(first)
    history.undo()
    history.add(second)
    #expect(history.redo() == false)
    #expect(history.annotations == [second])
}
