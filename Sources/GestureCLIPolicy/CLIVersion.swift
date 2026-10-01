import Foundation

/// The single explicit version source for the binary.
///
/// Development builds use the next release line with a `-dev` suffix. Before
/// tagging, remove the suffix: the release workflow compares the packaged
/// binary against the actual tag. There is no runtime git lookup.
public enum CLIVersion {
  public static let current = "0.3.0-dev"
}
