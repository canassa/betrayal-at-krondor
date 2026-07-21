{
  description = "1993-authentic Borland MAKE build of KRONDOR.EXE (Betrayal at Krondor)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # The vendored 1993 DOS toolchain (Borland bc20/bc30/bc31 + the FreeDOS
        # build image) is NOT committed — it's a hash-pinned tarball fetched here
        # and exposed to the build via $BAK_TOOLCHAIN. Museum-ware, freely
        # available; the hash pins exact content, which a byte-exact build needs.
        # To roll a new toolchain: rebuild toolchain.tar.gz, upload it as the
        # release asset below, and update `hash` (`nix hash file --sri toolchain.tar.gz`).
        toolchainTar = pkgs.fetchurl {
          url = "https://github.com/canassa/betrayal-at-krondor/releases/download/toolchain-v1/toolchain.tar.gz";
          hash = "sha256-mcg60E93xQOzeVEnZFgQ95d+ZHUU6RoD2ixpfZPcjfs=";
        };
        toolchain = pkgs.runCommand "dos-toolchain" { } ''
          mkdir -p $out
          ${pkgs.gnutar}/bin/tar -xzf ${toolchainTar} -C $out
        '';
      in {
        devShells.default = pkgs.mkShell {
          # Python is NOT from nix — uv installs and manages it, so use
          # `uv run bak build`. bcc/tasm/tlink run *inside* the FreeDOS qemu VMs
          # (built from $BAK_TOOLCHAIN), driven by the bak CLI.
          packages = with pkgs; [
            uv           # uv-managed Python — `uv run bak build`
            qemu         # qemu-system-i386: the FreeDOS build VMs (KVM for bc31/asm, TCG for the bc2 band)
            mtools       # mcopy/mmd — stage the bak/ tree into the FreeDOS disk image
            clang-tools  # clang-format — `bak format` / the pre-commit hook (never tree-wide)
            lefthook     # git hooks — see lefthook.yml; run `lefthook install` once
            doxygen      # API docs from the /** */ comments — `doxygen Doxyfile`
            graphviz     # `dot` — struct collaboration diagrams for the doxygen HTML
          ];

          # Expose the fetched toolchain; paths.py reads $BAK_TOOLCHAIN (falling
          # back to ./toolchain if unset, e.g. outside the nix shell).
          BAK_TOOLCHAIN = toolchain;

          shellHook = ''
            echo "bak shell   ::  uv=$(uv --version 2>&1)  qemu=$(qemu-system-i386 --version 2>/dev/null | head -1)"
            echo "            ::  toolchain=$BAK_TOOLCHAIN"
          '';
        };
      });
}
