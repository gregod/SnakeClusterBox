#! /usr/bin/env nix-shell
#! nix-shell -i bash -p wireguard-tools

KEY_DIR="./keys"

if [ -d "$KEY_DIR" ]; then
    echo "Using existing wireguard keys in $KEY_DIR"
else
    echo "Generating new wireguard keys"
    mkdir $KEY_DIR
    for i in {0..20}
    do
        wg genkey | tee "$KEY_DIR/$i.priv" | wg pubkey > "$KEY_DIR/$i.pub"
    done
fi


echo "Building Iso"
nix-build '<nixpkgs/nixos>' -A config.system.build.isoImage -I nixos-config=configuration.nix
