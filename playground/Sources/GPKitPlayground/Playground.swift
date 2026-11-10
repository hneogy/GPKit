// The playground's module: GPKit behind six exported functions, for the page's script on gpkit.gppasses.com.
//
//   gpkit_alloc(size) -> pointer       memory for the page to write the pasted text into
//   gpkit_free(pointer)                gives it back
//   gpkit_read(text, length) -> size   the element sets as GPKit reads them, and each one's TLE or GPKit's reason
//   gpkit_now(text, length, index, latitude, longitude, height, unixTime) -> size
//                                      where one of them is from a place at an instant, and its light
//   gpkit_passes(text, length, index, latitude, longitude, height, unixStart, seconds, above) -> size
//                                      its passes over the place, each with when it can be seen
//   gpkit_answer() -> pointer          the last answer, as UTF-8 JSON of the size the call gave
//
// The answers are PlaygroundAnswers', the same code playground-reference runs natively, so CI holds the two equal.
// The module asks nothing of the network, reads no clock and keeps nothing between calls but the last answer.
// Heights are in metres, angles in degrees, times in seconds from 1970 January 1 UTC as the page's Date gives them.
import PlaygroundAnswers

nonisolated(unsafe) var answer: UnsafeMutableBufferPointer<UInt8>?

/// Keeps a JSON text as the last answer and gives its size in bytes.
func give(_ text: String) -> Int32 {
    answer?.deallocate()
    let bytes = Array(text.utf8)
    let kept = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: max(bytes.count, 1))
    _ = kept.initialize(from: bytes)
    answer = kept
    return Int32(bytes.count)
}

/// The text the page wrote into memory.
func text(_ pointer: UnsafeRawPointer, _ length: Int32) -> String {
    String(decoding: UnsafeRawBufferPointer(start: pointer, count: Int(length)), as: UTF8.self)
}

#if arch(wasm32)
@_expose(wasm, "gpkit_alloc")
#endif
@_cdecl("gpkit_alloc")
public func gpkitAlloc(_ size: Int32) -> UnsafeMutableRawPointer {
    UnsafeMutableRawPointer.allocate(byteCount: Int(max(size, 1)), alignment: 1)
}

#if arch(wasm32)
@_expose(wasm, "gpkit_free")
#endif
@_cdecl("gpkit_free")
public func gpkitFree(_ pointer: UnsafeMutableRawPointer) {
    pointer.deallocate()
}

#if arch(wasm32)
@_expose(wasm, "gpkit_answer")
#endif
@_cdecl("gpkit_answer")
public func gpkitAnswer() -> UnsafeMutableRawPointer? {
    answer.map { UnsafeMutableRawPointer($0.baseAddress!) }
}

#if arch(wasm32)
@_expose(wasm, "gpkit_read")
#endif
@_cdecl("gpkit_read")
public func gpkitRead(_ pointer: UnsafeRawPointer, _ length: Int32) -> Int32 {
    give(Answers.read(text(pointer, length)))
}

#if arch(wasm32)
@_expose(wasm, "gpkit_now")
#endif
@_cdecl("gpkit_now")
public func gpkitNow(_ pointer: UnsafeRawPointer, _ length: Int32, _ index: Int32, _ latitude: Double, _ longitude: Double,
                     _ height: Double, _ unixTime: Double) -> Int32 {
    give(Answers.now(text(pointer, length), index: index, latitude: latitude, longitude: longitude, height: height, unixTime: unixTime))
}

#if arch(wasm32)
@_expose(wasm, "gpkit_passes")
#endif
@_cdecl("gpkit_passes")
public func gpkitPasses(_ pointer: UnsafeRawPointer, _ length: Int32, _ index: Int32, _ latitude: Double, _ longitude: Double,
                        _ height: Double, _ unixStart: Double, _ seconds: Double, _ above: Double) -> Int32 {
    give(Answers.passes(text(pointer, length), index: index, latitude: latitude, longitude: longitude, height: height,
                        unixStart: unixStart, seconds: seconds, above: above))
}
