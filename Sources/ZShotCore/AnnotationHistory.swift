public struct AnnotationHistory: Equatable, Sendable {
    public private(set) var annotations: [Annotation] = []
    public private(set) var undone: [Annotation] = []

    public init() {}

    public mutating func add(_ annotation: Annotation) {
        annotations.append(annotation)
        undone.removeAll()
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let last = annotations.popLast() else { return false }
        undone.append(last)
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let last = undone.popLast() else { return false }
        annotations.append(last)
        return true
    }
}
