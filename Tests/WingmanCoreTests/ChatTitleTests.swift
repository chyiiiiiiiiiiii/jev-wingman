import Testing
@testable import WingmanCore

@Test func titlesReadFromAccessibilityMustMatchExactly() {
    #expect(ChatTitle.same("#開發", "#開發 ", tolerant: false))
    #expect(!ChatTitle.same("#開發", "#開發群", tolerant: false))
    // The old check compared only the first four characters.
    #expect(!ChatTitle.same("Flutter Taipei", "Flutter Tokyo", tolerant: false))
    #expect(!ChatTitle.same("", "", tolerant: false))
}

@Test func ocrTitlesMayDifferByOneMisreadCharacterWhenLongEnough() {
    #expect(ChatTitle.same("Flutter Taipei", "Flutter Taipel", tolerant: true))
    // Short names differ by one letter between different people.
    #expect(!ChatTitle.same("Amy Lin", "Amy Liu", tolerant: true))
    #expect(!ChatTitle.same("Flutter Taipei", "Flutter Tokyo", tolerant: true))
}
