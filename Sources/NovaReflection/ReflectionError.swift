//
//  Created by Carson Rau on 3/31/22.
//

/// An error in the reflection framework.
public enum ReflectionError: Error {
    case noTypeInfo(type: Any.Type, kind: Kind)
    case noPointer(type: Any.Type, value: Any)
    case noProperty(name: String)
    case constructionError(type: Any.Type)
    case accessError(name: String, type: Any.Type)
}
