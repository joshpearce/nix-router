# Testable helper functions for router configuration
{ lib }:
{
  # Parse VLAN ID to subnet (e.g., 84 -> "10.13.84.0/24")
  vlanToSubnet = vlanId: "10.13.${toString vlanId}.0/24";

  # Get gateway IP for a VLAN (e.g., 84 -> "10.13.84.1")
  vlanToGateway = vlanId: "10.13.${toString vlanId}.1";

  # Parse an IP address into octets
  parseIp =
    ip:
    let
      parts = lib.splitString "." ip;
    in
    if builtins.length parts == 4 then map lib.strings.toInt parts else null;

  # Check if IP is in a given VLAN subnet (10.13.X.0/24)
  ipInVlan =
    ip: vlanId:
    let
      octets = lib.splitString "." ip;
    in
    builtins.length octets == 4
    && builtins.elemAt octets 0 == "10"
    && builtins.elemAt octets 1 == "13"
    && builtins.elemAt octets 2 == toString vlanId;

  # Check if IP is in RFC1918 private range
  isPrivateIp =
    ip:
    let
      parts = lib.splitString "." ip;
      o1 = lib.strings.toInt (builtins.elemAt parts 0);
      o2 = lib.strings.toInt (builtins.elemAt parts 1);
    in
    builtins.length parts == 4
    && (o1 == 10 || (o1 == 172 && o2 >= 16 && o2 <= 31) || (o1 == 192 && o2 == 168));

  # Validate DNS hostname label per RFC 1123
  # - Lowercase letters, digits, hyphens only
  # - Must start and end with letter or digit
  # - Max 63 characters
  isValidDnsName = name: builtins.match "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$" name != null;

  # Validate DHCP pool configuration
  # Pool should not include gateway (.1) or reserved range
  validateDhcpPool =
    {
      poolOffset,
      poolSize,
      reservedStart ? 1,
      reservedEnd ? 20,
    }:
    let
      poolStart = poolOffset;
      poolEnd = poolOffset + poolSize - 1;
    in
    {
      valid = poolStart > reservedEnd && poolEnd <= 254;
      inherit poolStart poolEnd;
      error =
        if poolStart <= reservedEnd then
          "Pool starts in reserved range (${toString reservedStart}-${toString reservedEnd})"
        else if poolEnd > 254 then
          "Pool extends beyond .254"
        else
          null;
    };

  # Validate static lease is in correct VLAN subnet
  validateStaticLease =
    { address, vlanId }:
    let
      octets = lib.splitString "." address;
      thirdOctet = if builtins.length octets >= 3 then builtins.elemAt octets 2 else "";
    in
    {
      valid = thirdOctet == toString vlanId;
      inherit address;
      expectedVlan = vlanId;
      actualThirdOctet = thirdOctet;
    };
}
