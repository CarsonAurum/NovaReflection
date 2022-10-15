//
//  Created by Carson Rau on 3/31/22.
//

import NovaCore
import NovaCRT

// MARK: - ClassHeader

struct ClassHeader {
    var isPointer: Int
    var strongRetainCount: Int32
    var weakRetainCount: Int32
    
    static func size() -> Int {
        MemoryLayout<ClassHeader>.size
    }
}

// MARK: - ClassMetadataLayout

struct AnyClassMetadataLayout {
    var _kind: Int
    var superclass: Any.Type
    #if !swift(>=5.4) || canImport(ObjectiveC)
    var runtimeReserve: (Int, Int)
    var roDataPtr: Int
    #endif
    var isSwiftClass: Bool {
        #if !swift(>=5.4) || canImport(ObjectiveC)
        return (roDataPtr & classIsSwiftMask()) != 0
        #else
        return true
        #endif
        
    }
}

struct ClassMetadataLayout: NominalMetadataLayoutType {
    var _kind: Int
    var superclass: Any.Type
    #if !swift(>=5.4) || canImport(ObjectiveC)
    var runtimeReserve: (Int, Int)
    var roDataPtr: Int
    #endif
    var flags: Int32
    var instanceAddressPtr: UInt32
    var instanceSize: UInt32
    var instanceAlignmentMask: UInt16
    var reserved: UInt16
    var classSize: UInt32
    var classAddressPtr: UInt32
    var typeDescriptor: UnsafeMutablePointer<ClassTypeDescriptor>
    var iVarDestroyer: UnsafeRawPointer
}

// MARK: - ClassTypeDescriptor

struct ClassTypeDescriptor: TypeDescriptor {
    var flags: ContextDescriptorFlags
    var parent: Int32
    var mangledName: RelativePointer<Int32, CChar>
    var fieldTypesAccessor:  RelativePointer<Int32, Int>
    var fieldDescriptor: RelativePointer<Int32, FieldDescriptor>
    var superclass: RelativePointer<Int32, Any.Type>
    var negativeSizeAndBoundsUnion: NegativeSizeAndBoundsUnion
    var metadataPositiveSizeInWords: Int32
    var immediateMemberCount: Int32
    var fieldCount: Int32
    var offsetToFieldOffsetVector: RelativeVectorPointer<Int32, Int>
    var genericContextHeader: TypeGenericDescriptorHeader
    
    struct NegativeSizeAndBoundsUnion: Union {
        var raw: Int32
        var metadataNegativeSizeInWords: Int32 {
            raw
        }
        mutating func resilientMetadataBounds() -> UnsafeMutablePointer<RelativePointer<Int32, StoredClassMetadataBounds>> {
            bind()
        }
    }
}

struct StoredClassMetadataBounds {
    var immediateMembersOffset: Int
    var bounds: MetadataBounds
}

struct MetadataBounds {
    var negativeSizeWods: UInt32
    var positiveSizeWods: UInt32
}

// MARK: - EnumMetadataLayout

struct EnumMetadataLayout: NominalMetadataLayoutType {
    var _kind: Int
    var typeDescriptor: UnsafeMutablePointer<EnumTypeDescriptor>
}

// MARK: - EnumTypeDescriptor
struct EnumTypeDescriptor: TypeDescriptor {
    var flags: ContextDescriptorFlags
    var parent: RelativePointer<Int32, UnsafeRawPointer>
    var mangledName: RelativePointer<Int32, CChar>
    var accessFunctionPointer: RelativePointer<Int32, UnsafeRawPointer>
    var fieldDescriptor: RelativePointer<Int32, FieldDescriptor>
    var payloadCaseCountAndPayloadSizeOffset: UInt32
    var emptyCaseCount: UInt32
    var offsetToFieldOffsetVector: RelativeVectorPointer<Int32, Int32>
    var genericContextHeader: TypeGenericDescriptorHeader
    
    var fieldCount: Int32 {
        get { 0 }
        set { }
    }
}

// MARK: - ExistentialContainer

struct ExistentialContainer {
    let buffer: ExistentialContainerBuffer
    let type: Any.Type
    let witnessTable: Int
}

struct ExistentialContainerBuffer {
    let buf1: Int
    let buf2: Int
    let buf3: Int
    
    static func size() -> Int {
        MemoryLayout<ExistentialContainerBuffer>.size
    }
}


// MARK: - FieldDescriptor

struct FieldDescriptor {
    var mangledTypeNameOffset: Int32
    var superclassOffset: Int32
    var _kind: UInt16
    var fieldCount: Int32
    var fields: Vector<FieldRecord>
    var kind: FieldDescriptor.Kind {
        .init(rawValue: _kind)!
    }
    
    enum Kind: UInt16 {
        case `struct`
        case `class`
        case `enum`
        case payloadEnum
        case `protocol`
        case classProtocol
        case objcProtocol
        case objcClass
    }
}

struct FieldRecord {
    var flags: Int32
    var _mangledTypeName: RelativePointer<Int32, Int8>
    var _fieldName: RelativePointer<Int32, Int8>
    var isVar: Bool { (flags & 0x2) == 0x2 }
    mutating func fieldName() -> String {
        .init(cString: _fieldName.advanced())
    }
    mutating func type(genericContext: UnsafeRawPointer?, genericArguments: UnsafeRawPointer?) -> Any.Type {
        let typeName = _mangledTypeName.advanced()
        let ptr = swift_getTypeByMangledNameInContext(
            typeName,
            getSymbolicMangledNameLength(typeName),
            genericContext,
            genericArguments?.assumingMemoryBound(to: Optional<UnsafeRawPointer>.self)
        )!
        return -*>ptr
    }
    func getSymbolicMangledNameLength(_ base: UnsafeRawPointer) -> Int32 {
        var end = base
        while let current = Optional(end.load(as: UInt8.self)), current != 0 {
            end += 1
            if current >= 0x1 && current <= 0x17 {
                end += 4
            } else if current >= 0x18 && current <= 0x1F {
                end += MemoryLayout<Int>.size
            }
        }
        return .init(end - base)
    }
}

// MARK: - FunctionMetadataLayout

struct FunctionMetadataLayout: MetadataLayoutType {
    var _kind: Int
    var flags: Int
    var arguments: Vector<Any.Type>
}

// MARK: - MetadataLayoutType

protocol MetadataLayoutType {
    var _kind: Int { get set }
}

protocol NominalMetadataLayoutType: MetadataLayoutType {
    associatedtype Descriptor: TypeDescriptor
    var typeDescriptor: UnsafeMutablePointer<Descriptor> { get set }
}

// MARK: - ProtocolDescriptor

struct ProtocolDescriptor {
    var ptr: Int
    var mangledName: UnsafeMutablePointer<CChar>
    var inheritedProtocols: Int
    var requiredInstanceMethods: Int
    var requiredClassMethods: Int
    var optionalInstanceMethods: Int
    var optionalClassMethods: Int
    var instanceProperties: Int
    var descriptorSize: Int32
    var flags: Int32
}

// MARK: - ProtocolMetadataLayout

struct ProtocolMetadataLayout: MetadataLayoutType {
    var _kind: Int
    var flags: Int
    var protocolCount: Int
    var protocolDescriptors: UnsafeMutablePointer<ProtocolDescriptor>
}

// MARK: - ProtocolTypeContainer

struct ProtocolTypeContainer {
    let type: Any.Type
    let witnessTable: Int
}

// MARK: - StructMetadataLayout

struct StructMetadataLayout: NominalMetadataLayoutType {
    var _kind: Int
    var typeDescriptor: UnsafeMutablePointer<StructTypeDescriptor>
}

// MARK: - StructTypeDescriptor

typealias FieldTypeAccessor = @convention(c) (UnsafePointer<Int>) -> UnsafePointer<Int>

struct StructTypeDescriptor: TypeDescriptor {
    var flags: ContextDescriptorFlags
    var parent: Int32
    var mangledName: RelativePointer<Int32, CChar>
    var functionPtr: RelativePointer<Int32, UnsafeRawPointer>
    var fieldDescriptor: RelativePointer<Int32, FieldDescriptor>
    var fieldCount: Int32
    var offsetToFieldOffsetVector: RelativeVectorPointer<Int32, Int32>
    var genericContextHeader: TypeGenericDescriptorHeader
}

// MARK: - GenericDescriptorHeader

struct TypeGenericDescriptorHeader {
    var instantiationCache: Int32
    var defaultPattern: Int32
    var base: GenericDescriptorHeader
}
struct GenericDescriptorHeader {
    var parameterCount: UInt16
    var requirementCount: UInt16
    var keyArgumentCount: UInt16
    var extraArgumentCount: UInt16
}

// MARK: - TupleMetadataLayout
struct TupleMetadataLayout: MetadataLayoutType {
    var _kind: Int
    var elementCount: Int
    var labels: UnsafeMutablePointer<CChar>
    var elements: Vector<TupleElementLayout>
}

struct TupleElementLayout {
    var type: Any.Type
    var offset: Int
}

// MARK: - TypeDescriptor

protocol TypeDescriptor {
    associatedtype FieldOffsetVectorOffsetType: FixedWidthInteger
    
    var flags: ContextDescriptorFlags { get set }
    var mangledName: RelativePointer<Int32, CChar> { get set }
    var fieldDescriptor: RelativePointer<Int32, FieldDescriptor> { get set }
    var fieldCount: Int32 { get set }
    var offsetToFieldOffsetVector: RelativeVectorPointer<Int32, FieldOffsetVectorOffsetType> { get set }
    var genericContextHeader: TypeGenericDescriptorHeader { get set }
}

typealias ContextDescriptorFlags = Int32

// MARK: - ValueWitnessTable

/// A vtable of functions that implement the value semantics of the type, providing fundamental
/// operations such as allocation, copying, and destruction of values of the type. The value
/// witness table also record the alignment, stride, size, and other fundamental properties of the
/// type. The VWT is at offset `-1` from the metadata pointer (immediately before the referenced
/// address).
struct ValueWitnessTable {
    
    var initializeBufferWithCopyOfBuffer: UnsafeRawPointer
    var destroy: UnsafeRawPointer
    var initializeWithCopy: UnsafeRawPointer
    var assignWithCopy: UnsafeRawPointer
    var initializeWithTake: UnsafeRawPointer
    var assignWithTake: UnsafeRawPointer
    var enumTagSinglePayload: UnsafeRawPointer
    var size: Int
    var stride: Int
    var flags: Int
    
    enum Flags {
        static let alignmentMask =      0x0000FFFF
        static let nonPOD =             0x00010000
        static let nonInline =          0x00020000
        static let extraInhabitants =   0x00040000
        static let spareBits =          0x00080000
        static let nonBitwise =         0x00100000
        static let enumWitnesses =      0x00200000
    }
    
}
