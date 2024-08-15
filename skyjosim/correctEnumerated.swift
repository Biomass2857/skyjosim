import Foundation

extension Array {
    func correctEnum() -> some Sequence<(Int, Element)> {
        zip(self.indices, self)
    }
}
