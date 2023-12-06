{ config, pkgs, lib, ... }:

let


  metadata = lib.importTOML ./hosts.toml;

  python-snake = import ./snakemake.nix { inherit lib; additionalPythonDeps = metadata.snakemake.python_deps; python = pkgs.python3; fetchFromGitHub = pkgs.fetchFromGitHub; };
  env-path = "/tmp/conda-env";
  conda-env = import ./conda-env.nix { inherit pkgs env-path; };
  submit-py = import ./schedule_sbatch.py.nix { python = python-snake; writeScript = pkgs.writeScript; };

  conda-bash-bin = pkgs.writeScriptBin "bash-conda" ''
    #!${conda-env}/bin/conda-fhs
    export SHELL="${conda-env}/bin/conda-fhs"
    ${pkgs.bash}/bin/bash $@
  '';

  slurmmake = pkgs.writeScriptBin "slurmmake" ''
    #!${conda-bash-bin}/bin/bash-conda
    ${python-snake}/bin/snakemake -j 1000 --default-resources mem_mb=1024 --use-conda --conda-frontend conda --cluster "${submit-py} {dependencies}" --immediate-submit --notemp --jobscript ${pkgs.writeText "jobscript.sh" ''
        #!${conda-env}/bin/conda-fhs
        # properties = {properties}
        export SHELL="${conda-env}/bin/conda-fhs"
        {exec_job}
    ''} $@
  '';

  conda-bin = pkgs.writeScriptBin "conda" ''
    #!${conda-env}/bin/conda-fhs
    ${env-path}/bin/conda $@
  '';


  build_config = hostIndex: hostData:
    let

      wireguard_ip = i: "${metadata.network.wireguard_net_prefix}${toString (i+1)}";
      wireguard_private = i: lib.readFile (./keys + "/${toString i}.priv");
      wireguard_public = i: lib.readFile (./keys + "/${toString i}.pub");


    in
    {
      "${hostData.name}" = {
        configuration = {





          services.munge.enable = true;
          systemd.tmpfiles.rules = [
            # strong authentication is via wireguard, so fixed shared random key is fine
            "f /etc/munge/munge.key 0400 munge munge - 9e9bd852f32ce8e8723ad5b8205162df60c1c80a"
          ];

          networking.hostName = hostData.name;
          networking.useDHCP = false;
          networking.nameservers = [ metadata.network.dns ];
          networking.interfaces.eth0.ipv4.addresses = [{ address = hostData.static_ip; prefixLength = 24; }];
          networking.defaultGateway.address = metadata.network.gateway;

          networking.extraHosts = lib.concatStringsSep "\n" (lib.filter (x: ! lib.hasSuffix hostData.name x)
            (lib.lists.imap1 (i: v: "${wireguard_ip i} ${v.name}") metadata.hosts));


          networking.firewall.allowedUDPPorts = [ 51820 ];
          networking.firewall.trustedInterfaces = [ "wg0" ];
          networking.wireguard.interfaces.wg0 = {
            ips = [ "${wireguard_ip hostIndex}/24" ];
            listenPort = 51820;
            privateKey = wireguard_private hostIndex;
            peers = (lib.filter (x: x.endpoint != "${wireguard_ip hostIndex}:51820")
              (lib.lists.imap1
                (i: v: {

                  publicKey = wireguard_public i;
                  allowedIPs = [ "${wireguard_ip i}/32" ];
                  endpoint = "${v.static_ip}:51820";


                })
                metadata.hosts));

          };


          #automatic registration of nodes
          systemd.services.slurmd = {
            serviceConfig.ExecStart = lib.mkForce (pkgs.writeShellScript "auto-slurm" "slurmd -Z");
            
            # mounted shared drive
            requires = ["shared.mount"];
            after = ["shared.mount"];
          };
          


          services.getty.greetingLine = lib.mkForce
            ''
              Snake Cluster Box

                        This is ${hostData.name} reachable at ${hostData.static_ip} / ${wireguard_ip hostIndex}
                        ${if (hostData.name == "master") then "This is the master node!" else "" }
                        ${if (hostData.worker) then "This is a worker node" else "" }
            '';
          services.getty.helpLine = lib.mkForce "";

          services.slurm = {
            controlAddr = "master";
            controlMachine = "master";
            server.enable = (hostData.name == "master");
            client.enable = hostData.worker;
            partitionName = [ "all Nodes=ALL default=YES MaxTime=INFINITE" ];
            procTrackType = "proctrack/cgroup";
            extraConfig = ''
              SchedulerType=sched/backfill 
              SelectType=select/cons_tres
              TaskPlugin=task/cgroup,task/affinity
              SelectTypeParameters=CR_CPU_Memory
              SlurmctldParameters=cloud_reg_addrs
              TreeWidth=65533
              CommunicationParameters=NoAddrCache
              MaxNodeCount=100
              PropagateResourceLimitsExcept=MEMLOCK
              CpuSpecList=0 # reserve cpu 0 for system
            '';

            extraCgroupConfig = ''        
              ConstrainCores=yes
              ConstrainDevices=yes
              ConstrainRAMSpace=yes
              ConstrainSwapSpace=yes
            '';
          };

          # nfs
          services.nfs.server = lib.mkIf (hostData.name == "master") {
            enable = true;
            hostName = wireguard_ip hostIndex;
            exports = "/shared         ${metadata.network.wireguard_net_prefix}.0/24(rw,nohide,insecure,no_subtree_check)";
          };

          fileSystems = {
            "/shared" =
              if (hostData.name == "master") then {
                device = "none";
                fsType = "tmpfs";
                options = [ "size=3G" "mode=755" "uid=1100"  "noatime" "nodiratime"];
              } else {
                device = "master:/shared";
                fsType = "nfs";
                options = [ "noatime" "nodiratime"];
              };
          };

        };
      };
    };
in
{
  imports = [
    <nixpkgs/nixos/modules/profiles/minimal.nix>
    ./iso-image.nix
  ];

  # Disable some other stuff we don't need.
  security.sudo.enable = lib.mkDefault false;
  services.udisks2.enable = lib.mkDefault false;

  hardware.cpu.intel.updateMicrocode = true;
  boot.kernelParams = [ "mitigations=off" ];
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Allow the user to log in as root with basic password.
  users.users.root.password = lib.mkIf (lib.hasAttr "root_pw" metadata.access) metadata.access.root_pw;
  console.keyMap = "de";
  services.openssh = {
    enable = true;
    openFirewall = true;
  };

  users.users."${metadata.access.main_user}" = {
    uid = 1100;
    isNormalUser = true;
    home = "/shared";
    openssh.authorizedKeys.keys = metadata.access.sshkeys;
  };


  # run miniconda installer upon boot, before slurm
  systemd.services.conda-expand = {
    serviceConfig = {
      ExecStart = pkgs.writeScript "init-conda" ''
        #!${conda-env}/bin/conda-fhs
        /usr/bin/conda-install
        conda config --set channel_priority strict
      '';
      Type = "oneshot";
      User = metadata.access.main_user;
      Group = "users";
      Environment = "HOME=/shared";
    };
    wantedBy = [ "multi-user.target" ];
    before = [ "slurmd.service" ];
  };


  users.users.root = {
    openssh.authorizedKeys.keys = metadata.access.sshkeys;
  };


  # Causes a lot of uncached builds for a negligible decrease in size.
  environment.noXlibs = lib.mkOverride 500 false;


  fonts.fontconfig.enable = lib.mkForce false;


  specialisation = lib.mkMerge (lib.lists.imap1 build_config metadata.hosts);

  i18n.defaultLocale = "en_US.UTF-8";
  environment.systemPackages = [
    python-snake
    conda-bash-bin
    conda-bin
    slurmmake

    pkgs.git
    pkgs.vim
    pkgs.lm_sensors
    
    pkgs.rustup
  ];


  xdg.icons.enable = false;
  xdg.mime.enable = false;
  xdg.sounds.enable = false;

  networking = {
    hostName = lib.mkDefault "snakeclusterbox";
  };

  isoImage.squashfsCompression =  "lz4";

  # ISO naming.
  isoImage.isoName = "snakeclusterbox.iso";

  isoImage.volumeID = lib.substring 0 11 "SNAKOS_ISO";

  # EFI booting
  isoImage.makeEfiBootable = true;

  # USB booting
  isoImage.makeUsbBootable = true;

  # There is no state living past a single boot into whichever version this was built with
  system.stateVersion = lib.trivial.release;

}
