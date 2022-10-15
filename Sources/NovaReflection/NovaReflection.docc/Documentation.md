# ``NovaReflection``

A runtime reflection library permitting high-level runtime abilities: type metadata access, 
reflection property setting, type construction for native swift types, and more.

## Topics

### Type Data

- ``TypeInfo``
- ``PropertyInfo``
- ``FunctionInfo``
- ``Case``
- ``Kind``

### Accessing Type Data

- ``typeInfo(of:)``
- ``functionInfo(of:)-35fa8``
- ``functionInfo(of:)-7wpqe``

### Constructing Types

- ``createInstance(of:constructor:)``
- ``createInstance(constructor:)``

### Other Utilities

- ``ReflectionError``
- ``DefaultConstructible``
- ``weakRetainCounts(of:)``
- ``retainCounts(of:)``
