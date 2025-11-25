_:
let
  routerVlanIp = "10.13.86.1";
  k3sServer1Ip = "10.13.86.111";
  k3sServer2Ip = "10.13.86.112";
  k3sServer3Ip = "10.13.86.113";
  asn = "65130";
  k3sServerAsn = "65131";
in
{
  config = {
    services.frr = {
      bgpd = {
        enable = true;
        extraOptions = [
          "--listenon ${routerVlanIp}"
        ];
      };
      config = ''
        router bgp ${asn}
          bgp router-id  ${routerVlanIp}
          neighbor ${k3sServer1Ip} remote-as ${k3sServerAsn}
          neighbor ${k3sServer2Ip} remote-as ${k3sServerAsn}
          neighbor ${k3sServer3Ip} remote-as ${k3sServerAsn}
      '';
    };
  };
}
