import Darwin

internal struct DynamicLibrary: @unchecked Sendable {
    private let handle: UnsafeMutableRawPointer?

    init(path: String) {
        self.handle = dlopen(path, RTLD_LAZY)
    }

    func symbol<T>(_ name: String, as type: T.Type = T.self) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(pointer, to: type)
    }
}
