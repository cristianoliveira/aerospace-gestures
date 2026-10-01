import Foundation

/// The single explicit version source for the binary.
///
/// Release tooling tags `v<current>`; `CHANGELOG.md` documents a `## v<current>`
/// section for it. A package test enforces the changelog pairing so the binary
/// version and the release records cannot drift apart. There is no runtime git
/// lookup: the value is baked in at compile time.
public enum CLIVersion {
  public static let current = "0.2.0"
}
