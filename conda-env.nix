# Adapted from 
#     https://github.com/NixOS/nixpkgs/issues/26245#issuecomment-304974959  by jluttine / Jaakko Luttinen 
#
#     https://github.com/bhipple/nixpkgs/blob/c5ca4af66a8121d36e744ca0b8de3007188c2e35/pkgs/tools/package-management/conda/default.nix
#     Used under MIT License, Copyright (c) 2003-2023 Eelco Dolstra and the Nixpkgs/NixOS contributors
#
# Modified to use chroot

{ pkgs ? import <nixpkgs> {}, env-path ? "/tmp/conda-env" }:

let

  # Conda installs it's packages and environments under this directory
  installationPath = env-path;

  # Downloaded Miniconda installer
  minicondaScript = pkgs.stdenv.mkDerivation rec {
    name = "miniconda-${version}";
    version = "py311_23.5.2-0";
    src = pkgs.fetchurl {
      url = "https://repo.continuum.io/miniconda/Miniconda3-${version}-Linux-x86_64.sh";
      sha256 = "sha256-Y012315InESt5AhVUrl768eG1JJF7RqDACKwtAbeWBc=";
    };
    # Nothing to unpack.
    unpackPhase = "true";
    # Rename the file so it's easier to use. The file needs to have .sh ending
    # because the installation script does some checks based on that assumption.
    # However, don't add it under $out/bin/ becase we don't really want to use
    # it within our environment. It is called by "conda-install" defined below.
    installPhase = ''
      mkdir -p $out
      cp $src $out/miniconda.sh
    '';
    # Add executable mode here after the fixup phase so that no patching will be
    # done by nix because we want to use this miniconda installer in the FHS
    # user env.
    fixupPhase = ''
      chmod +x $out/miniconda.sh
    '';
  };

  # Wrap miniconda installer so that it is non-interactive and installs into the
  # path specified by installationPath
  conda-install = pkgs.runCommand "conda-install"
    { buildInputs = [ pkgs.makeWrapper minicondaScript ]; }
    ''
      mkdir -p $out/bin
      makeWrapper                            \
        ${minicondaScript}/miniconda.sh      \
        $out/bin/conda-install               \
        --add-flags "-p ${installationPath}" \
        --add-flags "-b"
    '';

in
(
  pkgs.buildFHSEnvChroot {
    name = "conda-fhs";
    targetPkgs = pkgs: (
      with pkgs; [
        conda-install
        gcc
        rustup
        gnumake
        which
      ]
    );
    profile = ''
      # Add conda to PATH
      export PATH=${installationPath}/bin:$PATH
      # Paths for gcc if compiling some C sources with pip/rust
      export NIX_CFLAGS_COMPILE="-I${installationPath}/include"
      export NIX_CFLAGS_LINK="-L${installationPath}/lib"
    '';
  }
)
