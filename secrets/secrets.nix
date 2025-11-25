{ config, ... }:
{
  age.secrets = {
    ses-smtp-user = {
      file = ./ses-smtp-user.age;
      owner = config.private.user.name;
      mode = "0440";
    };
    healthchecks-io-ping-key = {
      file = ./healthchecks-io-ping-key.age;
      owner = config.private.user.name;
      mode = "0440";
    };
    aws-domain-mgr-key-id = {
      file = ./aws-domain-mgr-key-id.age;
      owner = config.private.user.name;
      mode = "0440";
    };
    aws-domain-mgr-secret = {
      file = ./aws-domain-mgr-secret.age;
      owner = config.private.user.name;
      mode = "0440";
    };
    ts-oauth-client-id = {
      file = ./router-ts-oauth-client-id.age;
      owner = config.private.user.name;
      mode = "0440";
    };
    ts-oauth-client-secret = {
      file = ./router-ts-oauth-client-secret.age;
      owner = config.private.user.name;
      mode = "0440";
    };
  };
}
