import Streamdown
import Testing
@testable import StreamdownUI

@MainActor
@Test func renderModelPublishesParsedMarkdown() async {
    let model = StreamdownRenderModel()

    await model.render(
        content: "Hello **world**",
        mode: .static,
        parseIncompleteMarkdown: false,
        normalizeHtmlIndentation: false
    )

    for _ in 0..<100 where model.snapshot.blocks.isEmpty {
        try? await Task.sleep(for: .milliseconds(10))
    }

    #expect(model.snapshot.blocks.count == 1)
}

@MainActor
@Test func codeBlockStatePublishesUpdatedContent() async {
    let state = CodeBlockRenderState(code: "let value = 1", language: "swift")

    state.update(code: "let value = 2", language: "swift")

    for _ in 0..<100 where state.lineTexts != ["let value = 2"] {
        try? await Task.sleep(for: .milliseconds(10))
    }

    #expect(state.normalizedCode == "let value = 2")
    #expect(state.lineTexts == ["let value = 2"])
    #expect(state.renderVersion > 1)
}

@MainActor
@Test func codeBlockStatePublishesThemeChanges() async {
    let state = CodeBlockRenderState(code: "// note", language: "swift")
    let initialVersion = state.renderVersion

    state.updateAppearance(foreground: .red, secondaryLabel: .blue)

    for _ in 0..<100 where state.renderVersion == initialVersion {
        try? await Task.sleep(for: .milliseconds(10))
    }

    #expect(state.renderVersion > initialVersion)
}
