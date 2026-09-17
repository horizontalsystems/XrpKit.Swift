# XrpKit.Swift

XRP Ledger kit for iOS, in the style of the other Horizontal Systems `*Kit.Swift` libraries.
Parity target: [`xrp-kit-android`](https://github.com/horizontalsystems/xrp-kit-android).

Status: the kit is complete locally and untagged — crypto, canonical binary codec, secp256k1 signer, JSON-RPC provider with endpoint failover, sync (account, ledger, trust lines, history), GRDB storage, submission with node fallback and the public `Kit` facade, all covered by the offline test suite. Design of record: Unstoppable Wallet iOS spec `docs/specs/2026-09-16-xrp-integration-design.md` (workstream B).

Test fixtures `Tests/XrpKitTests/Fixtures/*.json` come from [xrpl.js](https://github.com/XRPLF/xrpl.js) (ripple-binary-codec), ISC license.

## Planned scope

- Keys: secp256k1 at `m/44'/144'/0'/0/0` from a BIP39 seed; classic `r...` addresses and X-addresses.
- Sync: `server_state`, `account_info`, `account_lines`, `account_tx` over JSON-RPC with endpoint failover; reserve from the network.
- Sending: `Payment` (XRP and issued currencies, destination tag, memo) and `TrustSet`, canonical binary codec, RFC 6979 low-S DER signatures, `LastLedgerSequence` on every submission.
- Storage: GRDB, one database per wallet id. State published with Combine.
