# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  config,
  lib,
  pkgs,
  agenix,
  ...
}:
{
  imports = [
    ./hardware2.nix

    # Private configuration options (values come from the 'private' flake input)
    ./private-options.nix
    ./my-options.nix

    ./dnsproxy.nix
    ./firewall.nix
    ./networkd.nix
    ./network-irq.nix
    ./node-exporter.nix
    ./ulogd.nix
    ./update-public-ip.nix
    ./users.nix
    ./vector.nix
    #./ups.nix
    ./bgp.nix
    ./tailscale.nix
    ./email.nix
    ./vscode-server.nix
    ./dry-activate.nix

    ./modules/vector.nix # copied vector implementation from pkgs, and change config from TOML to JSON, because I had some issue...
    ./secrets/secrets.nix

  ];

  my = {
    vsCodeServer = true;
    emailSending = {
      enable = true;
      from = "router@${config.private.domain}";
    };
    tailscale = {
      enable = true;
      netfilterModeOff = true;
      enableSsh = true;
      subnetRoutes = [
        "192.168.1.0/24"
        #"10.13.84.181/32"
        #"10.13.93.50/32"
        "10.13.0.0/16"
      ];
      tags = [ "tag:router" ];
      extraUpFlags = [ "--accept-dns=false" ];
    };
  };

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = true;
      "net.netfilter.nf_conntrack_acct" = "1";
    };
  };

  time.timeZone = "America/New_York";

  system.includeBuildDependencies = false;

  environment.systemPackages = with pkgs; [
    pciutils
    tcpdump
    awscli
    jq
    netcat-gnu
    runitor
    prometheus-node-exporter
    agenix.packages.x86_64-linux.default
    nftables
    nixfmt-rfc-style
    nodejs_24
    git
    uv
    statix
    deadnix
    age
  ];

  programs.nix-ld.enable = true;

  networking = {
    hostName = "nix-router";
    nameservers = [ "10.13.84.1" ];
    dhcpcd.enable = false;
    inherit (config.private) hosts;
  };

  services = {
    resolved.enable = false;
    openssh = {
      enable = true;
      ports = [
        22
        8044
      ];
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
      };
    };

    chrony = {
      enable = true;
      servers = [
        "time1.facebook.com"
        "time2.facebook.com"
        "time3.facebook.com"
        "time4.facebook.com"
        "time5.facebook.com"
      ];
      serverOption = "iburst";
      enableRTCTrimming = false;
      initstepslew = false;
      extraConfig = ''
        maxupdateskew 100.0
        rtcsync
        makestep 1 3
      '';
    };

    udev = {
      extraRules = ''
        ACTION=="add", SUBSYSTEM=="module", KERNEL=="nf_conntrack", \
                 RUN+="${pkgs.systemd}/lib/systemd/systemd-sysctl --prefix=/net/netfilter"
      '';
    };

    avahi = {
      enable = true;
      nssmdns4 = true;
      reflector = true;
      allowInterfaces = [
        "lan"
        "iot"
        "hazmat"
      ];
    };
  };

  environment.etc = {
    "systemd/journald.conf".text = lib.mkForce ''
      [Journal]
      Storage=volatile
      RateLimitInterval=30s
      RateLimitBurst=10000
    '';
  };

  # https://search.nixos.org/options?channel=21.11&show=system.stateVersion&from=0&size=50&sort=relevance&type=packages&query=stateVersion
  system.stateVersion = "21.05"; # Did you read the comment?

  security.sudo.wheelNeedsPassword = false;

}
