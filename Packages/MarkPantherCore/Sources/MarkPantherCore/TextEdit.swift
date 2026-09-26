import Foundation

/// A single text replacement to be applied to an `NSTextView`'s text storage.
///
/// All ranges are expressed in UTF-16 code units (`NSRange`), matching
/// `NSString`/`NSTextStorage` semantics so callers can apply them directly.
public struct TextEdit: Equatable, Sendable {
    /// The range in the *original* text that should be replaced.
    public var range: NSRange
    /// The string to substitute into `range`.
    public var replacement: String
    /// The selection to apply *after* `replacement` has been substituted,
    /// expressed in the coordinate space of the resulting text.
    public var selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }
}
