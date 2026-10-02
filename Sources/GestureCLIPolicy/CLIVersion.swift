import Foundation

/// The single explicit version source for the binary.
///
/// Set this to the release version before tagging: the release workflow compares
/// the packaged binary against the actual tag. There is no runtime git lookup.
public enum CLIVersion {
  public static let current = "0.3.0"
}
