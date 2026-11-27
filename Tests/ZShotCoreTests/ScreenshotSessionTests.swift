import CoreGraphics
import Testing
import ZShotCore

private let mainDisplay = CGRect(x: 0, y: 0, width: 1440, height: 900)
private let sideDisplay = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
private let frontWindow = CGRect(x: 100, y: 100, width: 300, height: 200)
private let backWindow = CGRect(x: 50, y: 50, width: 800, height: 600)

private func makeSession(mouse: CGPoint = CGPoint(x: 10, y: 10)) -> ScreenshotSession {
    ScreenshotSession(displays: [mainDisplay, sideDisplay], windows: [frontWindow, backWindow], style: ToolStyle(), mouse: mouse)
}

private func selected(_ session: ScreenshotSession) -> CGRect? {
    if case .annotating(let selection, _) = session.phase { return selection }
    return nil
}

private func drag(_ session: inout ScreenshotSession, from start: CGPoint, to end: CGPoint) {
    _ = session.handle(.mouseDown(start))
    _ = session.handle(.mouseDragged(end))
    _ = session.handle(.mouseUp(end))
}

private func annotatingSession() -> ScreenshotSession {
    var session = makeSession()
    drag(&session, from: CGPoint(x: 1000, y: 800), to: CGPoint(x: 1400, y: 850))
    return session
}

@Test func dragSelectsTheNormalizedArea() {
    var session = makeSession()
    drag(&session, from: CGPoint(x: 500, y: 400), to: CGPoint(x: 200, y: 100))
    #expect(selected(session) == CGRect(x: 200, y: 100, width: 300, height: 300))
}

@Test func dragAcrossDisplaysSpansBoth() {
    var session = makeSession()
    drag(&session, from: CGPoint(x: 1400, y: 100), to: CGPoint(x: 1500, y: 200))
    #expect(selected(session) == CGRect(x: 1400, y: 100, width: 100, height: 100))
}

@Test func hoverHighlightsFrontmostWindowUnderMouse() {
    var session = makeSession()
    _ = session.handle(.mouseMoved(CGPoint(x: 150, y: 150)))
    #expect(session.phase == .choosing(hover: frontWindow))
    _ = session.handle(.mouseMoved(CGPoint(x: 600, y: 500)))
    #expect(session.phase == .choosing(hover: backWindow))
    _ = session.handle(.mouseMoved(CGPoint(x: 1000, y: 800)))
    #expect(session.phase == .choosing(hover: nil))
}

@Test func clickSelectsHoveredWindow() {
    var session = makeSession()
    let point = CGPoint(x: 150, y: 150)
    _ = session.handle(.mouseMoved(point))
    drag(&session, from: point, to: point)
    #expect(selected(session) == frontWindow)
}

@Test func dragUnderThresholdCountsAsClick() {
    var session = makeSession()
    drag(&session, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 153, y: 147))
    #expect(selected(session) == frontWindow)
}

@Test func dragAtThresholdSelectsArea() {
    var session = makeSession()
    drag(&session, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 160, y: 160))
    #expect(selected(session) == CGRect(x: 150, y: 150, width: 10, height: 10))
}

@Test func clickOnNothingKeepsChoosing() {
    var session = makeSession()
    drag(&session, from: CGPoint(x: 1000, y: 800), to: CGPoint(x: 1000, y: 800))
    #expect(session.phase == .choosing(hover: nil))
}

@Test func windowsArrivingLaterAreClippedAndHovered() {
    var session = ScreenshotSession(displays: [mainDisplay], windows: [], style: ToolStyle(), mouse: CGPoint(x: 20, y: 20))
    session.setWindows([CGRect(x: -100, y: -100, width: 200, height: 200)])
    #expect(session.phase == .choosing(hover: CGRect(x: 0, y: 0, width: 100, height: 100)))
}

@Test func fullDisplaySelectsDisplayUnderMouse() {
    var session = makeSession(mouse: CGPoint(x: 2000, y: 500))
    _ = session.handle(.command(.fullDisplay))
    #expect(selected(session) == sideDisplay)
}

@Test func drawUndoRedo() {
    var session = annotatingSession()
    drag(&session, from: CGPoint(x: 1100, y: 810), to: CGPoint(x: 1200, y: 840))
    let arrow = Annotation(
        shape: .arrow(from: CGPoint(x: 1100, y: 810), to: CGPoint(x: 1200, y: 840)), swatch: .red, thickness: .medium)
    #expect(session.history.annotations == [arrow])

    let undo = session.handle(.command(.undo))
    #expect(undo == nil)
    #expect(session.history.annotations.isEmpty)
    let redo = session.handle(.command(.redo))
    #expect(redo == nil)
    #expect(session.history.annotations == [arrow])
}

@Test func undoWithNothingLeftCancels() {
    var session = annotatingSession()
    drag(&session, from: CGPoint(x: 1100, y: 810), to: CGPoint(x: 1200, y: 840))
    let firstUndo = session.handle(.command(.undo))
    #expect(firstUndo == nil)
    let secondUndo = session.handle(.command(.undo))
    #expect(secondUndo == .cancel)
}

@Test func undoWhileChoosingCancels() {
    var session = makeSession()
    let undo = session.handle(.command(.undo))
    #expect(undo == .cancel)
}

@Test func escCancelsFromAnyPhase() {
    var choosing = makeSession()
    let fromChoosing = choosing.handle(.command(.cancel))
    #expect(fromChoosing == .cancel)
    var annotating = annotatingSession()
    let fromAnnotating = annotating.handle(.command(.cancel))
    #expect(fromAnnotating == .cancel)
}

@Test func degenerateAnnotationsAreDropped() {
    var session = annotatingSession()
    drag(&session, from: CGPoint(x: 1100, y: 810), to: CGPoint(x: 1100, y: 810))
    _ = session.handle(.command(.selectTool(.rectangle)))
    drag(&session, from: CGPoint(x: 1100, y: 810), to: CGPoint(x: 1200, y: 810))
    _ = session.handle(.command(.selectTool(.pen)))
    drag(&session, from: CGPoint(x: 1100, y: 810), to: CGPoint(x: 1100, y: 810))
    #expect(session.history.annotations.isEmpty)
}

@Test func penKeepsEveryPoint() {
    var session = annotatingSession()
    _ = session.handle(.command(.selectTool(.pen)))
    _ = session.handle(.mouseDown(CGPoint(x: 1100, y: 810)))
    _ = session.handle(.mouseDragged(CGPoint(x: 1110, y: 820)))
    _ = session.handle(.mouseDragged(CGPoint(x: 1120, y: 815)))
    _ = session.handle(.mouseUp(CGPoint(x: 1130, y: 830)))
    let points = [CGPoint(x: 1100, y: 810), CGPoint(x: 1110, y: 820), CGPoint(x: 1120, y: 815), CGPoint(x: 1130, y: 830)]
    #expect(session.history.annotations.map(\.shape) == [.pen(points)])
}

@Test func styleChangesApplyToNextAnnotation() {
    var session = annotatingSession()
    _ = session.handle(.command(.selectTool(.circle)))
    _ = session.handle(.command(.selectSwatch(.blue)))
    _ = session.handle(.command(.selectThickness(.thick)))
    drag(&session, from: CGPoint(x: 1100, y: 810), to: CGPoint(x: 1150, y: 830))
    let expected = Annotation(shape: .ellipse(CGRect(x: 1100, y: 810, width: 50, height: 20)), swatch: .blue, thickness: .thick)
    #expect(session.history.annotations == [expected])
}

@Test func shiftConstrainsTheDraftLive() {
    var session = annotatingSession()
    _ = session.handle(.command(.selectTool(.rectangle)))
    _ = session.handle(.mouseDown(CGPoint(x: 1100, y: 810)))
    _ = session.handle(.mouseDragged(CGPoint(x: 1150, y: 830)))
    #expect(session.annotations.map(\.shape) == [.rectangle(CGRect(x: 1100, y: 810, width: 50, height: 20))])
    _ = session.handle(.shiftChanged(true))
    #expect(session.annotations.map(\.shape) == [.rectangle(CGRect(x: 1100, y: 810, width: 50, height: 50))])
    _ = session.handle(.mouseUp(CGPoint(x: 1150, y: 830)))
    #expect(session.history.annotations.map(\.shape) == [.rectangle(CGRect(x: 1100, y: 810, width: 50, height: 50))])
}

@Test func finishReturnsSelectionAndAnnotationsIncludingDraft() {
    var session = annotatingSession()
    _ = session.handle(.command(.selectTool(.line)))
    drag(&session, from: CGPoint(x: 1100, y: 810), to: CGPoint(x: 1200, y: 810))
    _ = session.handle(.mouseDown(CGPoint(x: 1100, y: 820)))
    _ = session.handle(.mouseDragged(CGPoint(x: 1300, y: 820)))
    let outcome = session.handle(.command(.finish))
    let lines: [Shape] = [
        .line(from: CGPoint(x: 1100, y: 810), to: CGPoint(x: 1200, y: 810)),
        .line(from: CGPoint(x: 1100, y: 820), to: CGPoint(x: 1300, y: 820)),
    ]
    let annotations = lines.map { Annotation(shape: $0, swatch: .red, thickness: .medium) }
    #expect(outcome == .finish(selection: CGRect(x: 1000, y: 800, width: 400, height: 50), annotations: annotations))
}

@Test func finishDoesNothingBeforeASelection() {
    var session = makeSession()
    let outcome = session.handle(.command(.finish))
    #expect(outcome == nil)
    #expect(session.phase == .choosing(hover: nil))
}
