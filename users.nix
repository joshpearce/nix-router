{ config, lib, ... }:
{
  users = {
    users = {
      ${config.private.user.name} = {
        isNormalUser = true;
        home = "/home/${config.private.user.name}";
        description = config.private.user.fullName;
        extraGroups = [
          "wheel"
          "networkmanager"
        ];
        openssh.authorizedKeys.keys = config.private.user.sshKeys;
      };
      proxyuser = {
        isNormalUser = true;
        home = "/home/proxyuser";
        description = "Proxy User";
        extraGroups = [ ];
        openssh.authorizedKeys.keys = config.private.proxyUser.sshKeys;
      };
    };
  };

  # Git configuration
  environment.etc."gitconfig".text = ''
    [user]
      name = ${config.private.user.fullName}
      email = ${config.private.user.email}
    [pull]
      ff = only
    [init]
      defaultBranch = main
    [core]
      editor = nano
  '';

  # Secret symlinks and directories
  system.activationScripts.userSecretsSetup = lib.stringAfter [ "agenix" ] ''
    mkdir -p /home/${config.private.user.name}/.agesecrets /home/${config.private.user.name}/bin
    chown ${config.private.user.name}:users /home/${config.private.user.name}/.agesecrets /home/${config.private.user.name}/bin

    ln -sf ${config.age.secrets.healthchecks-io-ping-key.path} /home/${config.private.user.name}/.agesecrets/healthchecks-io-ping-key
    ln -sf ${config.age.secrets.aws-domain-mgr-key-id.path} /home/${config.private.user.name}/.agesecrets/aws-domain-mgr-key-id
    ln -sf ${config.age.secrets.aws-domain-mgr-secret.path} /home/${config.private.user.name}/.agesecrets/aws-domain-mgr-secret

    find /home/${config.private.user.name}/.agesecrets -xtype l -delete 2>/dev/null || true
    find /home/${config.private.user.name}/bin -xtype l -delete 2>/dev/null || true
  '';
}
