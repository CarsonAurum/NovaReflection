//
//  Created by Carson Rau on 3/31/22.
//

import NovaCore

func metadataPointer(type: Any.Type) -> UnsafeMutablePointer<Int> {
    -*>type
}

func metadata(of type: Any.Type) throws -> MetadataInfo {
    let kind = Kind(type: type)
    switch kind {
    case .struct:
        return StructMetadata(type: type)
    case .class:
        return ClassMetadata(type: type)
    case .existential:
        return ProtocolMetadata(type: type)
    case .tuple:
        return TupleMetadata(type: type)
    case .enum:
        return EnumMetadata(type: type)
    default:
        throw ReflectionError.noTypeInfo(type: type, kind: kind)
    }
}

func swiftObject() -> Any.Type {
    class Temp { }
    let md = ClassMetadata(type: Temp.self)
    return md.pointer.pointee.superclass
}

func classIsSwiftMask() -> Int {
    #if canImport(Darwin)
    if #available(macOS 10.14.4, iOS 12.2, tvOS 12.2, watchOS 5.2, *) {
        return 2
    }
    #endif
    return 1
}

// MARK: - MetadataType

protocol MetadataInfo {
    var kind: Kind { get }
    var size: Int { get }
    var alignment: Int { get }
    var stride: Int { get }
    init(type: Any.Type)
}

protocol MetadataType: MetadataInfo, TypeInfoConvertible {
    associatedtype Layout: MetadataLayoutType
    
    var pointer: UnsafeMutablePointer<Layout> { get set }
    init(pointer: UnsafeMutablePointer<Layout>)
}

extension MetadataType {
    init(type: Any.Type) {
        self = .init(pointer: -*>type)
    }
    var type: Any.Type {
        -*>pointer
    }
    var kind: Kind {
        .init(flag: pointer.pointee._kind)
    }
    var size: Int { valueWitnessTable.pointee.size }
    var alignment: Int { (valueWitnessTable.pointee.flags & ValueWitnessTable.Flags.alignmentMask) + 1 }
    var stride: Int { valueWitnessTable.pointee.stride }
    var valueWitnessTable: UnsafeMutablePointer<ValueWitnessTable> {
        pointer
            .raw
            .advanced(by: -MemoryLayout<UnsafeRawPointer>.size)
            .assumingMemoryBound(to: UnsafeMutablePointer<ValueWitnessTable>.self)
            .pointee
        
    }
    mutating func toTypeInfo() -> TypeInfo {
        return TypeInfo(metadata: self)
    }
}

// MARK: - NominalMetadataType

protocol NominalMetadataType: MetadataType where Layout: NominalMetadataLayoutType {
    var genericArgumentOffset: Int { get }
}

extension NominalMetadataType {
    var genericArgumentOffset: Int { 2 }
    var isGeneric: Bool { (pointer.pointee.typeDescriptor.pointee.flags & 0x80) != 0 }
    mutating func mangledName() -> String {
        .init(cString: pointer.pointee.typeDescriptor.pointee.mangledName.advanced())
    }
    mutating func offsetCount() -> Int {
        .init(pointer.pointee.typeDescriptor.pointee.fieldCount)
    }
    mutating func fieldCount() -> Int {
        .init(pointer.pointee.typeDescriptor.pointee.fieldCount)
    }
    mutating func fieldOffsets() -> [Int] {
        pointer.pointee.typeDescriptor.pointee
            .offsetToFieldOffsetVector
            .vector(metadata: pointer.raw.assumingMemoryBound(to: Int.self), n: fieldCount())
            .map(numericCast)
    }
    mutating func properties() -> [PropertyInfo] {
        let offsets = fieldOffsets()
        let fieldDescriptor = pointer.pointee.typeDescriptor.pointee
            .fieldDescriptor
            .advanced()
        let genericVector = genericArgumentVector()
        return (0 ..< fieldCount()).map {
            let record = fieldDescriptor.pointee.fields.element(at: $0)
            return PropertyInfo(
                name: record.pointee.fieldName(),
                type: record.pointee.type(
                    genericContext: pointer.pointee.typeDescriptor,
                    genericArguments: genericVector
                ),
                isVar: record.pointee.isVar,
                offset: offsets[$0],
                owner: type
            )
        }
    }
    
    func genericArguments() -> UnsafeMutableBufferPointer<Any.Type> {
        guard isGeneric else { return .init(start: nil, count: 0) }
        let count = pointer.pointee.typeDescriptor.pointee.genericContextHeader.base.parameterCount
        return genericArgumentVector().buffer(n: .init(count))
    }
    func genericArgumentVector() -> UnsafeMutablePointer<Any.Type> {
        pointer.advanced(by: genericArgumentOffset, wordSize: MemoryLayout<UnsafeRawPointer>.size)
            .assumingMemoryBound(to: Any.Type.self)
    }
}

// MARK: - ClassMetadata

struct AnyClassMetadata {
    var pointer: UnsafeMutablePointer<AnyClassMetadataLayout>
    init(type: Any.Type) {
        pointer = -*>type
    }
    func asClassMetadata() -> ClassMetadata? {
        guard pointer.pointee.isSwiftClass else { return nil }
        let ptr = pointer.raw.assumingMemoryBound(to: ClassMetadataLayout.self)
        return ClassMetadata(pointer: ptr)
    }
}

struct ClassMetadata: NominalMetadataType {
    var pointer: UnsafeMutablePointer<ClassMetadataLayout>
    var hasResilientSuperclass: Bool {
        let descriptor = pointer.pointee.typeDescriptor
        return ((descriptor.pointee.flags >> 16) & 0x2000) != 0
    }
    var areImmediateMembersNegative: Bool {
        let descriptor = pointer.pointee.typeDescriptor
        return ((descriptor.pointee.flags >> 16) & 0x1000) != 0
    }
    var genericArgumentOffset: Int {
        let descriptor = pointer.pointee.typeDescriptor
        if !hasResilientSuperclass {
            return areImmediateMembersNegative ?
                -Int(descriptor.pointee.negativeSizeAndBoundsUnion.metadataNegativeSizeInWords)
                : Int(descriptor.pointee.metadataPositiveSizeInWords - descriptor.pointee.immediateMemberCount)
        }
        fatalError("Cannot get generic offsets for classes with a resilient superclass!")
    }
    func superclassMetadata() -> AnyClassMetadata? {
        let superclass = pointer.pointee.superclass
        guard superclass != swiftObject() else { return nil }
        return AnyClassMetadata(type: superclass)
    }
    mutating func toTypeInfo() -> TypeInfo {
        var info = TypeInfo(metadata: self)
        info.mangledName = mangledName()
        info.properties = properties()
        info.generics = .init(genericArguments())
        var superclass = superclassMetadata()?.asClassMetadata()
        while var sc = superclass {
            info.inheritance += sc.type
            let superInfo = sc.toTypeInfo()
            info.properties += superInfo.properties
            superclass = sc.superclassMetadata()?.asClassMetadata()
        }
        return info
    }
}
// MARK: - EnumMetadata

struct EnumMetadata: NominalMetadataType {
    var pointer: UnsafeMutablePointer<EnumMetadataLayout>
    var payloadCaseCount: UInt32 {
        pointer.pointee.typeDescriptor.pointee.payloadCaseCountAndPayloadSizeOffset & 0x00FFFFFF
    }
    var caseCount: UInt32 {
        pointer.pointee.typeDescriptor.pointee.emptyCaseCount + payloadCaseCount
    }
    mutating func cases() -> [Case] {
        guard pointer.pointee.typeDescriptor.pointee.fieldDescriptor.offset != 0 else {
            return []
        }
        let descriptor = pointer.pointee.typeDescriptor.pointee.fieldDescriptor.advanced()
        let genericVector = genericArgumentVector()
        return (0 ..< caseCount).map {
            let record = descriptor.pointee.fields.element(at: .init($0))
            return .init(
                name: record.pointee.fieldName(),
                payload: record.pointee._mangledTypeName.offset == 0 ? nil : record.pointee.type(
                    genericContext: pointer.pointee.typeDescriptor,
                    genericArguments: genericVector
                )
            )
        }
    }
    mutating func toTypeInfo() -> TypeInfo {
        var info = TypeInfo(metadata: self)
        info.mangledName = mangledName()
        info.cases = cases()
        info.generics = .init(genericArguments())
        info.caseCount = .init(caseCount)
        info.payloadCaseCount = .init(payloadCaseCount)
        return info
    }
}

// MARK: - FunctionMetadata

struct FunctionMetadata: MetadataType {
    var pointer: UnsafeMutablePointer<FunctionMetadataLayout>
    
    func info() -> FunctionInfo {
        let (argCount, argTypes, returnType) = argumentInfo()
        return .init(
            argumentCount: argCount,
            arguments: argTypes,
            return: returnType,
            throws: `throws`()
        )
    }
    
    private func argumentInfo() -> (Int, [Any.Type], Any.Type) {
        let n = argumentCount()
        let argTypeBuffer = pointer.pointee.arguments.vector(n: n + 1)
        let result = argTypeBuffer[0]
        let argTypes = Array(argTypeBuffer.dropFirst())
        return (n, argTypes, result)
    }
    
    private func argumentCount() -> Int {
        pointer.pointee.flags & 0x00FFFFFF
    }
    private func `throws`() -> Bool {
        (pointer.pointee.flags & 0x01000000) != 0
    }
}

// MARK: - ProtocolMetadata

struct ProtocolMetadata: MetadataType {
    var pointer: UnsafeMutablePointer<ProtocolMetadataLayout>
    mutating func mangledName() -> String {
        .init(cString: pointer.pointee.protocolDescriptors.pointee.mangledName)
    }
}

// MARK: - StructMetadata

struct StructMetadata: NominalMetadataType {
    var pointer: UnsafeMutablePointer<StructMetadataLayout>
    mutating func toTypeInfo() -> TypeInfo {
        var info = TypeInfo(metadata: self)
        info.properties = properties()
        info.mangledName = mangledName()
        info.generics = .init(genericArguments())
        return info
    }
}

// MARK: - TupleMetadata

struct TupleMetadata: MetadataType, TypeInfoConvertible {
    var pointer: UnsafeMutablePointer<TupleMetadataLayout>
    func elementCount() -> Int {
        pointer.pointee.elementCount
    }
    func labels() -> [String] {
        guard Int(bitPattern: pointer.pointee.labels) != 0 else {
            return (0 ..< elementCount()).map { _ in "" }
        }
        var labels = String(cString: pointer.pointee.labels).components(separatedBy: " ")
        labels.removeLast()
        return labels
    }
    func elements() -> UnsafeBufferPointer<TupleElementLayout> {
        pointer.pointee.elements.vector(n: elementCount())
    }
    func properties() -> [PropertyInfo] {
        let names = labels()
        let el = elements()
        let num = elementCount()
        var props = [PropertyInfo]()
        (0 ..< num).forEach {
            props += .init(
                name: names[$0],
                type: el[$0].type,
                isVar: true,
                offset: el[$0].offset,
                owner: type
            )
        }
        return props
    }
    mutating func toTypeInfo() -> TypeInfo {
        var info = TypeInfo(metadata: self)
        info.properties = properties()
        return info
    }
}
