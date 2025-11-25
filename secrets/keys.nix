let
  router = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINxprlqo/0T5dC2+qSI5IszztPXKRal+L6/FrGRGFC11";
  backup_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF4a0q3EjFbIgz4kOeS24UTObOXUj6tn9VgbTy5gek49";
  keys = [
    router
    backup_key
  ];
in
{
  "healthchecks-io-ping-key.age".publicKeys = keys;
  "ses-smtp-user.age".publicKeys = keys;
  "aws-domain-mgr-key-id.age".publicKeys = keys;
  "aws-domain-mgr-secret.age".publicKeys = keys;
  "router-ts-oauth-client-id.age".publicKeys = keys;
  "router-ts-oauth-client-secret.age".publicKeys = keys;
}
