# Snake Cluster Box

We introduce a [Snakemake](https://www.snakemake.org) and [Conda](https://anaconda.org/anaconda/conda) enabled, multi-node [SLURM](https://slurm.schedmd.com/) computation cluster that can be launched from a single USB stick and operates entirely in RAM. This setup enables us to temporarily borrow any computational resources from a lab. This software enables any researcher to establish a robust computation cluster using a straightforward configuration file, eliminating the need for specialized systems engineering or administration knowledge. Moreover, it diminishes reliance on centrally administered resources. 

## Build Prerequisites

* [Nix package manager](https://nixos.org):  Required for building the Linux image.
* [WireGuard](https://www.wireguard.com) CLI: Necessary for generating WireGuard keys.


## Preparing the USB Stick

This repository provides the tools to build a custom ISO that can be burned onto a USB stick. The network configuration and authentication information are embedded in the image. No job or experiment specific data will be included. Consequently, the USB stick can be reused for various projects within the same lab.

* Clone this repository and adapt the [Configuration File](./hosts.toml)  to suit   your requirements.
  All fields except for `root_pw` are mandatory. 

* Execute `sh ./buildIso.sh` to initiate the build process. This involves downloading and constructing a Linux image from scratch, which may take some time. Once completed, the ISO image can be located in the `result` folder.

* Burn the ISO onto a USB stick or CD.

* This stick can be used to boot any node of the cluster. As the cluster runs entirely in RAM, the stick can be removed after boot to start multiple machines in sequence. The appropriate profile can be chosen in the boot menu. The master node must always be booted first.


## Submitting Jobs & Software Envrionments
The cluster behaves like a normal SLURM cluster. 
We have made some extensions for and generally prefer running Snakemake workflows.
The master node contains a `slurmmake` binary, behaving like the standard `snakemake` binary but automatically submitting all jobs to the Slurm cluster. 
Additionally, it enables the Conda package manager.

A examplary workflow could therefore look as follows:
```
ssh master_node -A
git clone https://example.com/research
cd research
slurmmake
```

**Note that the entire cluster runs in RAM. 
Any results must be extracted from the master node before reboot**

## Trust and Security model

We adhere to the following trust model:

1. The system is reasonably secure against other users on the network.
   * The cluster's internal communications are secured using a Wireguard VPN mesh network.
   * Outside access is restricted to SSH using public key authentication, with all other ports closed by a firewall.

2. We assume that any authorized user (SSH, local root) is trustworthy.
3. The system boots into a login screen, and the machine can be left unattended with a strong `root_password` set.
4. The USB stick contains all secrets, and if lost, the system is compromised.
5. This software is experimental and has not undergone a security audit.




## License

SnakeClusterBox
Copyright (C) 2023  Gregor Godbersen

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.



 







