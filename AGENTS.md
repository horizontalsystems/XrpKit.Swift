# XrpKit Engineering Contract

## Repository boundary

This repository is the product authority for `XrpKit.Swift`. The integration branch is `main`.
Work on exactly one approved slice of the design at a time. The design of record is workstream B of
`docs/specs/2026-09-16-xrp-integration-design.md` in the Unstoppable Wallet iOS repository; changes to
the public `Kit` API go through that spec first.

## Evidence before repository changes

1. Use the `analog-driven-development` workflow with Gimle (`palace-memory`): every non-trivial
   structure mirrors a verified analog in `solana-kit-ios`, `StellarKit.Swift`, `TronKit.Swift` or
   `ThorChainKit.Swift`, and the analog is named in the pull request delta matrix.
2. Android `xrp-kit-android` is the behavioural reference (sync policy, failover, expiry, codec);
   iOS naming and layering follow the Horizontal Systems Swift kits, never the Kotlin file names.
3. Verify load-bearing analogs in the current tree (Serena / `rg`), not from memory.

## Product and acceptance boundaries

- `Sources/XrpKit` is UI-agnostic: Combine for state publication; no UIKit or SwiftUI imports.
- No third-party XRPL SDK. Signing uses `HsCryptoKit` (`Crypto.sign`: RFC 6979, low-S, DER);
  key derivation uses `HdWalletKit`. Dependencies are pinned with `exact:`.
- Tests run offline only: the xrpl.js binary-codec fixtures, the ripple-keypairs signing vector and
  stubbed RPC. There is no live-network test target; testnet is exercised manually.
- Never log transaction blobs, signatures, public keys, seeds or private keys.
- Never commit secrets, mnemonic phrases, provider credentials or host-local paths.
- Commit messages: plain descriptive sentences in the repository style, no attribution trailers.
