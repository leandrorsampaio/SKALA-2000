import Testing

@testable import DeskArt

struct FontTests {
    @Test func everyBundledFaceRegisters() {
        #expect(DeskFonts.missing.isEmpty)
    }
}
