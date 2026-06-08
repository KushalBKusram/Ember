import Testing
import Foundation
@testable import Ember

@Suite("Embedding round-trip")
struct EmbeddingRoundTripTests {

    @Test("Float array survives Data ↔ Array conversion")
    func roundTrip() {
        let original: [Float] = [0.1, -0.5, 1.0, 0, .pi, -.pi]
        let data = original.asData
        let restored = [Float](data: data)

        #expect(restored != nil)
        #expect(restored?.count == original.count)
        for (a, b) in zip(original, restored ?? []) {
            #expect(a == b)
        }
    }

    @Test("Empty Data returns nil, not empty array")
    func emptyDataIsNil() {
        let restored = [Float](data: Data())
        #expect(restored == nil)
    }

    @Test("Misaligned Data returns nil")
    func misalignedDataIsNil() {
        // 5 bytes is not a multiple of MemoryLayout<Float>.stride (4)
        let restored = [Float](data: Data([1, 2, 3, 4, 5]))
        #expect(restored == nil)
    }
}
