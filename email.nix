{
  config,
  lib,
  ...
}:

{

  config = {
    programs = lib.mkIf config.my.emailSending.enable {
      msmtp = {
        enable = true;
        accounts = {
          default = {
            auth = true;
            tls = true;
            inherit (config.my.emailSending)
              port
              from
              host
              user
              passwordeval
              ;
          };
        };
      };
    };
  };
}
