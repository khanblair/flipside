import Foundation

@MainActor
public final class InMemoryNoteStore {
    private var bodies: [ObjectIdentifier: String] = [:]

    public init() {}

    public func body(for key: ObjectIdentifier) -> String {
        bodies[key] ?? ""
    }

    public func setBody(_ body: String, for key: ObjectIdentifier) {
        bodies[key] = body
    }
}
