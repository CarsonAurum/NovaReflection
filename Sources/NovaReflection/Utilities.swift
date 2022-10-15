//
//  Created by Carson Rau on 3/31/22.
//

import NovaCore

// MARK: - Get/Set

protocol Getters { }
extension Getters {
    static func get(from pointer: UnsafeRawPointer) -> Any {
        pointer.assumingMemoryBound(to: Self.self).pointee
    }
}
func getters(type: Any.Type) -> Getters.Type {
    let container = ProtocolTypeContainer(type: type, witnessTable: 0)
    return -*>container
}

protocol Setters { }
extension Setters {
    static func set(value: Any, pointer: UnsafeMutableRawPointer, initialize: Bool = false) {
        if let value: Self = -?>value {
            let bound = pointer.assumingMemoryBound(to: self)
            if initialize {
                bound.initialize(to: value)
            } else {
                bound.pointee = value
            }
        }
    }
}
func setters(type: Any.Type) -> Setters.Type {
    let container = ProtocolTypeContainer(type: type, witnessTable: 0)
    return -*>container
}
// MARK: - Retain Count
///
///
/// - Parameter object:
/// - Returns:
/// - Throws:
public func retainCounts(of object: inout AnyObject) throws -> Int {
    try withValuePointer(of: &object) {
        return Int($0.assumingMemoryBound(to: ClassHeader.self).pointee.strongRetainCount)
    }
}
///
///
/// - Parameter object:
/// - Returns:
/// - Throws:
public func weakRetainCounts(of object: inout AnyObject) throws -> Int {
    try withValuePointer(of: &object) {
        return Int($0.assumingMemoryBound(to: ClassHeader.self).pointee.weakRetainCount)
    }
}
