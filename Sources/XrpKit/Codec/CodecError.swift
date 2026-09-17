import Foundation

public enum CodecError: Error, Equatable {
    case unsupportedField(String)
    case unsupportedTransactionType(String)
    case invalidValue(field: String)
    /// A number that does not fit the field's fixed width. The codec rejects rather than truncates.
    case valueOutOfRange(field: String)
    case invalidCurrencyCode(String)
    case invalidAmount(String)
    case lengthTooLarge(Int)
}
