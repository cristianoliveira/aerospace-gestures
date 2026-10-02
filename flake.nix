{
  description = "AeroSpace trackpad gestures for macOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          generated = pkgs.swiftpm2nix.helpers ./nix;
          package = pkgs.swiftPackages.stdenv.mkDerivation {
            pname = "aerospace-gestures";
            version = "0.3.0";
            src = self;

            nativeBuildInputs = [ pkgs.swift pkgs.swiftpm ];

            configurePhase = ''
              runHook preConfigure
              ${generated.configure}
              runHook postConfigure
            '';

            # Nix's Darwin SwiftPM lacks Apple's xctest runner. The repository's
            # canonical `make check` remains the test gate; this derivation is
            # still built entirely in the Nix sandbox from fixed dependencies.
            doCheck = false;

            installPhase = ''
              runHook preInstall
              install -Dm755 "$(swiftpmBinPath)/aerospace-gestures" \
                "$out/bin/aerospace-gestures"
              runHook postInstall
            '';

            meta = {
              description = "Map macOS trackpad gestures to commands";
              homepage = "https://github.com/cristianoliveira/aerospace-gestures";
              license = pkgs.lib.licenses.mit;
              mainProgram = "aerospace-gestures";
              platforms = pkgs.lib.platforms.darwin;
            };
          };
        in {
          default = package;
          aerospace-gestures = package;
        });

      checks = forAllSystems (system: {
        default = self.packages.${system}.default;
      });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in {
          default = pkgs.mkShellNoCC {
            packages = [ pkgs.git pkgs.gnumake ];
          };
        });
    };
}
