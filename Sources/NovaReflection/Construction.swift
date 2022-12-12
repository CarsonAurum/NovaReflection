//
//  Created by Carson Rau on 4/1/22.
//

import NovaCRT
import NovaCore
#if canImport(Foundation)
import Foundation
#endif

// MARK: - Factory
/// Create a new typed instance of a given value with a custom constructor.
///
/// - Parameter constructor: The custom constructor to use when initializing this value.
/// - Returns:The typed value if initialization completed successfully.
/// - Throws: ``ReflectionError/constructionError(type:)``
public func createInstance<T>(constructor: ((PropertyInfo) throws -> Any)? = nil) throws -> T {
    if let value: T = try -?>createInstance(of: T.self, constructor: constructor) {
        return value
    }
    throw ReflectionError.constructionError(type: T.self)
}
/// Create a new generic instance of a given type with a custom constructor.
///
/// - Parameters:
///   - type: The type to construct.
///   - constructor: The custom constructor to use when initializing this value.
/// - Returns: The generic/untyped value if iniitalization completed successfully.
/// - Throws: ``ReflectionError/constructionError(type:)``
public func createInstance(
    of type: Any.Type,
    constructor: ((PropertyInfo) throws -> Any)? = nil
) throws -> Any {
    if let defConstructor: DefaultConstructible.Type = -?>type {
        return defConstructor.init()
    }
    let kind = Kind(type: type)
    switch kind {
    case .struct:
        return try buildStruct(type: type, constructor: constructor)
    case .class:
        return try buildClass(type: type)
    default:
        throw ReflectionError.constructionError(type: type)
    }
}

func buildStruct(
    type: Any.Type,
    constructor: ((PropertyInfo) throws -> Any)? = nil
) throws -> Any {
    let info = try typeInfo(of: type)
    let ptr = UnsafeMutableRawPointer.allocate(
        byteCount: info.size,
        alignment: info.alignment
    )
    defer { ptr.deallocate() }
    try setProperties(typeInfo: info, pointer: ptr, constructor: constructor)
    return getters(type: type).get(from: ptr)
}
func buildClass(type: Any.Type) throws -> Any {
    var md = ClassMetadata(type: type)
    let info = md.toTypeInfo()
    let meta: UnsafeRawPointer = -*>type
    let instanceSize = Int32(md.pointer.pointee.instanceSize)
    let alignmentMask = Int32(md.pointer.pointee.instanceAlignmentMask)
    guard let val = swift_allocObject(meta, instanceSize, alignmentMask) else {
        throw ReflectionError.constructionError(type: type)
    }
    try setProperties(typeInfo: info, pointer: .init(mutating: val))
    return -*>val
}
func setProperties(
    typeInfo: TypeInfo,
    pointer: UnsafeMutableRawPointer,
    constructor: ((PropertyInfo) throws -> Any)? = nil
) throws {
    try typeInfo.properties.forEach { property in
        let val = try constructor.map { return try $0(property) }
                    ?? defaultValue(of: property.type)
        let valPtr = pointer.advanced(by: property.offset)
        let sets = setters(type: property.type)
        sets.set(value: val, pointer: valPtr, initialize: true)
    }
}
func defaultValue(of type: Any.Type) throws -> Any {
    if let constructable: DefaultConstructible.Type = -?>type {
        return constructable.init()
    } else if let isOpt: ExpressibleByNilLiteral.Type = -?>type {
        return isOpt.init(nilLiteral: ())
    }
    return try createInstance(of: type)
}

// MARK: - DefaultValue

/// A type constructible by an initializer with no parameters.
public protocol DefaultConstructible {
    /// The initializer.
    init()
}

extension Int: DefaultConstructible { }
extension Int8: DefaultConstructible { }
extension Int16: DefaultConstructible { }
extension Int32: DefaultConstructible { }
extension Int64: DefaultConstructible { }
extension UInt: DefaultConstructible { }
extension UInt8: DefaultConstructible { }
extension UInt16: DefaultConstructible { }
extension UInt32: DefaultConstructible { }
extension UInt64: DefaultConstructible { }
extension String: DefaultConstructible { }

extension Bool: DefaultConstructible { }
extension Double: DefaultConstructible { }
extension Float: DefaultConstructible { }

extension Array: DefaultConstructible { }
extension Dictionary: DefaultConstructible { }
extension Set: DefaultConstructible { }
extension Character: DefaultConstructible {
    public init() {
        self = " "
    }
}

#if canImport(Foundation)
extension Decimal: DefaultConstructible { }
extension Date: DefaultConstructible { }
extension UUID: DefaultConstructible { }
extension Data: DefaultConstructible { }
#endif
