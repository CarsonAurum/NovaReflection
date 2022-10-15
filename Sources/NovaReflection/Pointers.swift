//
//  Created by Carson Rau on 3/31/22.
//

import NovaCore

func withValuePointer<Value, Result>(
    of value: inout Value,
    _ body: (UnsafeMutableRawPointer) throws -> Result
) throws -> Result {
    let kind = Kind(type: Value.self)
    switch kind {
    case .struct:
        return try withUnsafePointer(to: &value) { try body($0.mutable.raw) }
    case .class:
        return try withClassValuePointer(of: &value, body)
    case .existential:
        return try withExistentialValuePointer(of: &value, body)
    default:
        throw ReflectionError.noPointer(type: Value.self, value: value)
    }
}

func withClassValuePointer<Value, Result>(
    of value: inout Value,
    _ body: (UnsafeMutableRawPointer) throws -> Result
) throws -> Result {
    try withUnsafePointer(to: &value) {
        try $0.withMemoryRebound(to: UnsafeMutableRawPointer.self, capacity: 1) {
            try body($0.pointee)
        }
    }
}

func withExistentialValuePointer<Value, Result>(
    of value: inout Value,
    _ body: (UnsafeMutableRawPointer) throws -> Result
) throws -> Result {
    try withUnsafePointer(to: &value) { ptr in
        try ptr.withMemoryRebound(to: ExistentialContainer.self, capacity: 1) {
            let container = $0.pointee
            let info = try metadata(of: container.type)
            if info.kind == .class || info.size > ExistentialContainerBuffer.size() {
                return try ptr.withMemoryRebound(to: UnsafeMutableRawPointer.self, capacity: 1) {
                    let base = $0.pointee
                    if info.kind == .struct {
                        return try body(base.advanced(by: existentialHeaderSize))
                    } else {
                        return try body(base)
                    }
                }
            } else {
                return try body($0.mutable.raw)
            }
        }
    }
}

var existentialHeaderSize: Int {
    MemoryLayout<Int>.size == 8 ? 16 : 8
}

// MARK: - RelativePointer

struct RelativePointer<Offset: FixedWidthInteger, Pointee>: CustomStringConvertible {
    var offset: Offset
    
    var description: String { "\(offset)" }
    
    mutating func pointee() -> Pointee {
        advanced().pointee
    }
    mutating func advanced() -> UnsafeMutablePointer<Pointee> {
        let offset = self.offset
        return withUnsafePointer(to: &self) {
            $0
                .raw
                .advanced(by: numericCast(offset))
                .assumingMemoryBound(to: Pointee.self)
                .mutable
        }
    }
}

// MARK: - RelativeVectorPointer

struct RelativeVectorPointer<Offset: FixedWidthInteger, Pointee>: CustomStringConvertible {
    var offset: Offset
    var description: String { "\(offset)" }
    mutating func vector(metadata: UnsafePointer<Int>, n: Int) -> UnsafeBufferPointer<Pointee> {
        metadata
            .advanced(by: numericCast(offset))
            .raw
            .assumingMemoryBound(to: Pointee.self)
            .buffer(n: n)
    }
}

// MARK: - Union

protocol Union {
    associatedtype Raw
    var raw: Raw { get set }
}

extension Union {
    mutating func bind<T>() -> UnsafeMutablePointer<T> {
        withUnsafePointer(to: &self) {
            $0.raw.assumingMemoryBound(to: T.self).mutable
        }
    }
}

// MARK: - Vector

struct Vector<Element> {
    var element: Element
    
    mutating func vector(n: Int) -> UnsafeBufferPointer<Element> {
        withUnsafePointer(to: &self) {
            $0.withMemoryRebound(to: Element.self, capacity: 1) { start in
                return start.buffer(n: n)
            }
        }
    }
    mutating func element(at i: Int) -> UnsafeMutablePointer<Element> {
        withUnsafePointer(to: &self) {
            $0.raw.assumingMemoryBound(to: Element.self).advanced(by: i).mutable
        }
    }
}
