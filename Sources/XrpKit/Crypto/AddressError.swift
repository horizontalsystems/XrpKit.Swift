import Foundation

public enum AddressError: Error {
    /// Not a classic `r...` address or an X-address: wrong alphabet, checksum, length or prefix.
    case invalidFormat
    /// An X-address of the other network (`T...` on mainnet or `X...` on testnet).
    case networkMismatch
    /// A typed destination tag contradicts the tag packed into the X-address.
    case tagConflict
}
