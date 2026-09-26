import Foundation

/// A three-step size preset for chrome that the user can scale.
///
/// 個々の pt を露出させずに段階で持つのは、ヘッダの帯・カプセル・ボタン・アイコンが
/// 互いに噛み合っているため。1つだけ動かすと信号ボタンとの高さが合わなくなる。
public enum InterfaceSize: String, Sendable, CaseIterable {
    case compact, regular, large

    /// Picks the value for this step from the three given in order.
    public func pick<T>(_ compact: T, _ regular: T, _ large: T) -> T {
        switch self {
        case .compact: return compact
        case .regular: return regular
        case .large: return large
        }
    }
}
