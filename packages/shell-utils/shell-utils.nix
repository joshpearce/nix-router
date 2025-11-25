{ pkgs }:
pkgs.writeShellScriptBin "is-private-ip" ''
  # Check if an IP is in RFC1918 private ranges
  # Returns 0 (true) if private, 1 (false) if public or invalid
  ip="$1"
  [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || exit 1
  IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
  [[ $o1 -eq 10 || ($o1 -eq 172 && $o2 -ge 16 && $o2 -le 31) || ($o1 -eq 192 && $o2 -eq 168) ]]
''
