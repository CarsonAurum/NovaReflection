//
//  Created by Carson Rau on 3/31/22.
//

import NovaCore

// MARK: - Case

/// A model of a single case from an enum.
public struct Case {
    /// The name of this enum case.
    public let name: String
    /// Any associated payload type(s) with this case.
    public let payload: Any.Type?
}

// MARK: - FunctionInfo
/// A model of a function containing reflection information.
public struct FunctionInfo {
    /// The number of arguments accepted by this function.
    public var argumentCount: Int
    /// The type of each argument accepted by this function in the order that the function accepts the parameters.
    public var arguments: [Any.Type]
    /// The return type of this function.
    public var `return`: Any.Type
    /// A boolean to determine if this function is a throwing function.
    public var `throws`: Bool
}
/// Access the function info of an associated function by instance.
///
/// - Parameter function: The function instance whose information is desired.
/// - Returns: The ``FunctionInfo`` corresponding to the given function
/// - Throws: A ``ReflectionError/noTypeInfo(type:kind:)`` error in the event that the given type is not a function.
public func functionInfo(of function: Any) throws -> FunctionInfo {
    try functionInfo(of: type(of: function))
}
/// Access the function info of an associated function by type.
///
/// - Parameter type: The function type whose information is desired.
/// - Returns: The ``FunctionInfo`` corresponding to the given function.
/// - Throws: A ``ReflectionError/noTypeInfo(type:kind:)`` error in the event that the giv en type is not a function.
public func functionInfo(of type: Any.Type) throws -> FunctionInfo {
    let kind = Kind(type: type)
    guard kind == .function else {
        throw ReflectionError.noTypeInfo(type: type, kind: kind)
    }
    return FunctionMetadata(type: type).info()
}

// MARK: - Kind

/// An enumeration representing all kind of data that can be stored within an `Any` value.
public enum Kind {
    /// Struct metadata is available for this type.
    case `struct`
    /// Enum metadata is available for this type.
    case `enum`
    /// The optional metadata for this type (shares consistency with enums; however differentiated
    /// for reflection purposes).
    case optional
    /// An opaque data type: referring to the use of `some Type` as a means of making some function more generic.
    case opaque
    /// A tuple data type.
    case tuple
    /// Function metadata is available for this type.
    case function
    case existential
    /// A type representative of another type.
    case metatype
    /// A class required to interoperate with Objective-C.
    case objcClass
    /// An existential type representative of another type.
    case existentialMetatype
    /// An unrecognized & unportable class that cannot be used within Swift.
    case foreignClass
    case heapLocalVariable
    case heapGenericLocalVariable
    /// An error type.
    case error
    /// A swift class not required to interoperate with Objective-C.
    case `class`
    init(flag: Int) {
        switch flag {
        case 1, (0 | Flags.nonHeap):
            self = .struct
        case 2, (1 | Flags.nonHeap):
            self = .enum
        case 3, (2 | Flags.nonHeap):
            self = .optional
        case 8, (0 | Flags.runtimePrivate | Flags.nonHeap):
            self = .opaque
        case 9, (1 | Flags.runtimePrivate | Flags.nonHeap):
            self = .tuple
        case 10, (2 | Flags.runtimePrivate | Flags.nonHeap):
            self = .function
        case 12, (3 | Flags.runtimePrivate | Flags.nonHeap):
            self = .existential
        case 13, (4 | Flags.runtimePrivate | Flags.nonHeap):
            self = .metatype
        case 14, (5 | Flags.runtimePrivate | Flags.nonHeap):
            self = .objcClass
        case 15, (6 | Flags.runtimePrivate | Flags.nonHeap):
            self = .existentialMetatype
        case 16, (3 | Flags.nonHeap):
            self = .foreignClass
        case 64, (0 | Flags.nonType):
            self = .heapLocalVariable
        case 65, (0 | Flags.nonType | Flags.runtimePrivate):
            self = .heapGenericLocalVariable
        case 128, (1 | Flags.nonType | Flags.runtimePrivate):
            self = .error
        default:
            self = .class
        }
    }
    
    init(type: Any.Type) {
        let pointer = metadataPointer(type: type)
        self = .init(flag: pointer.pointee)
    }
    fileprivate enum Flags {
        static let nonHeap = 0x200
        static let runtimePrivate = 0x100
        static let nonType = 0x400
    }
}

// MARK: - PropertyInfo
///
public struct PropertyInfo: Equatable {
    public let name: String
    public let type: Any.Type
    public let isVar: Bool
    public let offset: Int
    public let owner: Any.Type
    ///
    ///
    /// - Parameters:
    ///   - value:
    ///   - object:
    /// - Throws:
    public func set<T>(value: Any, on object: inout T) throws {
        try withValuePointer(of: &object) {
            try set(value: value, pointer: $0)
        }
    }
    ///
    ///
    /// - Parameters:
    ///   - value:
    ///   - object:
    /// - Throws:
    public func set(value: Any, on object: inout Any) throws {
        try withValuePointer(of: &object) { ptr in
            try set(value: value, pointer: ptr)
        }
    }
    ///
    ///
    /// - Parameters:
    ///   - value:
    ///   - pointer:
    /// - Throws:
    private func set(value: Any, pointer: UnsafeMutableRawPointer) throws {
        let valuePtr = pointer.advanced(by: offset)
        let sets = setters(type: type)
        sets.set(value: value, pointer: valuePtr)
    }
    ///
    ///
    /// - Parameter object:
    /// - Returns:
    /// - Throws:
    public func get<T>(from object: Any) throws -> T {
        if let value: T = try -?>get(from: object) {
            return value
        }
        throw ReflectionError.accessError(name: name, type: type)
    }
    ///
    ///
    /// - Parameter object:
    /// - Returns:
    /// - Throws:
    public func get(from object: Any) throws -> Any {
        var obj = object
        return try withValuePointer(of: &obj) {
            let valuePtr = $0.advanced(by: offset)
            let gets = getters(type: type)
            return gets.get(from: valuePtr)
        }
    }
    ///
    ///
    /// - Parameters:
    ///   - lhs:
    ///   - rhs:
    /// - Returns:
    public static func == (lhs: PropertyInfo, rhs: PropertyInfo) -> Bool {
        rhs.name == lhs.name
        && rhs.type == lhs.type
        && rhs.isVar == lhs.isVar
        && rhs.offset == lhs.offset
        && rhs.owner == lhs.owner
    }
}
// MARK: - TypeInfo
///
///
public struct TypeInfo {
    public var kind: Kind = .class
    public var name: String = ""
    public var type: Any.Type = Any.self
    public var mangledName: String = ""
    public var properties: [PropertyInfo] = []
    public var inheritance: [Any.Type] = []
    public var size: Int = 0
    public var alignment: Int = 0
    public var stride: Int = 0
    public var cases: [Case] = []
    public var caseCount: Int = 0
    public var payloadCaseCount: Int = 0
    public var generics: [Any.Type] = []
    ///
    ///
    /// - Parameter metadata:
    init<Metadata: MetadataType>(metadata: Metadata) {
        kind = metadata.kind
        size = metadata.size
        alignment = metadata.alignment
        stride = metadata.stride
        type = metadata.type
        name = .init(describing: metadata.type)
    }
    public var superclass: Any.Type? {
        inheritance.first
    }
    ///
    ///
    /// - Parameter named:
    /// - Returns:
    /// - Throws:
    public func property(named: String) throws -> PropertyInfo {
        if let prop = properties.first(where: { $0.name == named}) {
            return prop
        }
        throw ReflectionError.noProperty(name: named)
    }
}
///
///
/// - Parameter type:
/// - Returns:
/// - Throws:
public func typeInfo(of type: Any.Type) throws -> TypeInfo {
    let kind = Kind(type: type)
    var converted: TypeInfoConvertible
    switch kind {
    case .struct:
        converted = StructMetadata(type: type)
    case .class:
        converted = ClassMetadata(type: type)
    case .existential:
        converted = ProtocolMetadata(type: type)
    case .tuple:
        converted = TupleMetadata(type: type)
    case .enum, .optional:
        converted = EnumMetadata(type: type)
    default:
        throw ReflectionError.noTypeInfo(type: type, kind: kind)
    }
    return converted.toTypeInfo()
}

protocol TypeInfoConvertible {
    mutating func toTypeInfo() -> TypeInfo
}
