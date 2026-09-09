{ config, ... }:
let
  cfg = config.private;
  # Syslog facility codes (RFC 5424) - must match ulogd.nix settings
  LOCAL1 = "17"; # Flow logs (conntrack) + packet logs
  LOCAL2 = "18"; # DNS redirect logs
  LOCAL3 = "19"; # Encrypted DNS (DoT/DoH) logs
in
{
  config = {
    services = {
      vector2 = {
        enable = true;
        journaldAccess = true;
        settings = {
          timezone = "local";
          sources = {
            journald = {
              type = "journald";
              batch_size = 64;
              include_units = [ "ulogd" ];
              current_boot_only = false;
              since_now = true;
            };
            vector_logs = {
              type = "internal_logs";
            };
          };
          transforms = {
            # Route by syslog facility (set in ulogd.nix)
            filter_flow_logs = {
              type = "filter";
              inputs = [ "journald" ];
              condition = ''.SYSLOG_FACILITY == "${LOCAL1}"'';
            };
            filter_redirect_logs = {
              type = "filter";
              inputs = [ "journald" ];
              condition = ''.SYSLOG_FACILITY == "${LOCAL2}"'';
            };
            filter_dns_redirect = {
              type = "filter";
              inputs = [ "filter_redirect_logs" ];
              condition = ''starts_with(to_string(.message) ?? "", "DNS-REDIRECT: ")'';
            };
            filter_ntp_redirect = {
              type = "filter";
              inputs = [ "filter_redirect_logs" ];
              condition = ''starts_with(to_string(.message) ?? "", "NTP-REDIRECT: ")'';
            };
            filter_encrypted_dns_logs = {
              type = "filter";
              inputs = [ "journald" ];
              condition = ''.SYSLOG_FACILITY == "${LOCAL3}"'';
            };
            parse_ntp_redirect = {
              type = "remap";
              inputs = [ "filter_ntp_redirect" ];
              source = ''
                # Parse: NTP-REDIRECT: IN=iot OUT= MAC=... SRC=10.13.93.50 DST=8.8.8.8 ... PROTO=UDP SPT=12345 DPT=123
                kvs, err = parse_key_value(.message, field_delimiter: " ", accept_standalone_key: true)
                .iface = kvs.IN
                .src = kvs.SRC
                .dst = kvs.DST
                .proto = kvs.PROTO
                .spt = kvs.SPT
                .dpt = kvs.DPT
                .prefix = "ntp-redirect"
              '';
            };
            parse_dns_redirect = {
              type = "remap";
              inputs = [ "filter_dns_redirect" ];
              source = ''
                # Parse: DNS-REDIRECT: IN=iot OUT= MAC=... SRC=10.13.93.50 DST=8.8.8.8 ... PROTO=UDP SPT=12345 DPT=53
                kvs, err = parse_key_value(.message, field_delimiter: " ", accept_standalone_key: true)
                .iface = kvs.IN
                .src = kvs.SRC
                .dst = kvs.DST
                .proto = kvs.PROTO
                .spt = kvs.SPT
                .dpt = kvs.DPT
                .prefix = "dns-redirect"
              '';
            };
            parse_encrypted_dns = {
              type = "remap";
              inputs = [ "filter_encrypted_dns_logs" ];
              source = ''
                # Parse: ENCRYPTED-DNS: IN=lan OUT=enp1s0 MAC=... SRC=10.13.84.50 DST=1.1.1.1 ... PROTO=TCP SPT=12345 DPT=853
                kvs, err = parse_key_value(.message, field_delimiter: " ", accept_standalone_key: true)
                .iface = kvs.IN
                .src = kvs.SRC
                .dst = kvs.DST
                .proto = kvs.PROTO
                .spt = kvs.SPT
                .dpt = kvs.DPT
                .prefix = "encrypted-dns"
              '';
            };
            prep_for_metric = {
              type = "remap";
              inputs = [ "filter_flow_logs" ];
              source = ''
                message_parts, err = split(.message, " ", limit: 2) # [DESTROY] ORIG: ...
                message_parts, err = split(message_parts[1], ",", limit: 2)
                orig_parts, err = split(message_parts[0], " ", limit: 2)
                reply_parts, err = split(message_parts[1], " ", limit: 2)
                orig_kvs, err = parse_key_value(orig_parts[1])
                reply_kvs, err = parse_key_value(reply_parts[1])

                orig_src = orig_kvs.SRC
                orig_dst = orig_kvs.DST
                orig_proto = orig_kvs.PROTO
                orig_spt = orig_kvs.SPT
                orig_dpt = orig_kvs.DPT
                orig_pkts = orig_kvs.PKTS
                orig_bytes = to_int!(orig_kvs.BYTES)

                reply_src = reply_kvs.SRC
                reply_dst = reply_kvs.DST
                reply_proto = reply_kvs.PROTO
                reply_spt = reply_kvs.SPT
                reply_dpt = reply_kvs.DPT
                reply_pkts = reply_kvs.PKTS
                reply_bytes = to_int!(reply_kvs.BYTES)

                .orig_src = orig_src
                .orig_dst = orig_dst
                .orig_proto = orig_proto  
                .orig_spt = orig_spt
                .orig_dpt = orig_dpt
                .orig_pkts = orig_pkts
                .orig_bytes = orig_bytes  

                .reply_src = reply_src
                .reply_dst = reply_dst
                .reply_proto = reply_proto
                .reply_spt = reply_spt
                .reply_dpt = reply_dpt
                .reply_pkts = reply_pkts
                .reply_bytes = reply_bytes

                .total_bytes = orig_bytes + reply_bytes

                name, err = "src={{orig_src}} dst={{orig_dst}} proto={{orig_proto}} dpt={{orig_dpt}}"

                .name = name
                .prefix = "flow"

              '';
            };
            log_to_metric = {
              type = "log_to_metric";
              inputs = [ "prep_for_metric" ];
              metrics = [
                {
                  type = "counter";
                  increment_by_value = true;
                  field = "total_bytes";
                  tags = {
                    prefix = "{{prefix}}";
                  };
                  name = "{{name}}";
                  namespace = "traffic";

                }
              ];
            };
            aggregate = {
              type = "aggregate";
              inputs = [ "log_to_metric" ];
              interval_ms = 60000;
            };
            metric_to_log = {
              type = "metric_to_log";
              inputs = [ "aggregate" ];
            };
            post_aggregate = {
              type = "remap";
              inputs = [ "metric_to_log" ];
              source = ''
                message = .name
                m = {
                  "prefix": .tags.prefix,
                  "message": message,
                  "value": .counter.value
                }
                . = m
              '';
            };
          };
          tests = [
            {
              name = "DNS redirects are emitted only as DNS events";
              inputs = [
                {
                  insert_at = "filter_redirect_logs";
                  type = "log";
                  log_fields = {
                    SYSLOG_FACILITY = LOCAL2;
                    message = "DNS-REDIRECT: IN=iot OUT= SRC=10.13.93.50 DST=8.8.8.8 PROTO=UDP SPT=12345 DPT=53";
                  };
                }
              ];
              outputs = [
                {
                  extract_from = "parse_dns_redirect";
                  conditions = [
                    {
                      type = "vrl";
                      source = ''
                        assert_eq!(.prefix, "dns-redirect")
                        assert_eq!(.iface, "iot")
                        assert_eq!(.dpt, "53")
                      '';
                    }
                  ];
                }
              ];
              no_outputs_from = [ "parse_ntp_redirect" ];
            }
            {
              name = "NTP redirects are emitted only as NTP events";
              inputs = [
                {
                  insert_at = "filter_redirect_logs";
                  type = "log";
                  log_fields = {
                    SYSLOG_FACILITY = LOCAL2;
                    message = "NTP-REDIRECT: IN=lan OUT= SRC=10.13.84.20 DST=1.2.3.4 PROTO=UDP SPT=12345 DPT=123";
                  };
                }
              ];
              outputs = [
                {
                  extract_from = "parse_ntp_redirect";
                  conditions = [
                    {
                      type = "vrl";
                      source = ''
                        assert_eq!(.prefix, "ntp-redirect")
                        assert_eq!(.iface, "lan")
                        assert_eq!(.dpt, "123")
                      '';
                    }
                  ];
                }
              ];
              no_outputs_from = [ "parse_dns_redirect" ];
            }
            {
              name = "Unrecognized redirect events are dropped";
              inputs = [
                {
                  insert_at = "filter_redirect_logs";
                  type = "log";
                  log_fields = {
                    SYSLOG_FACILITY = LOCAL2;
                    message = "OTHER-REDIRECT: IN=iot SRC=10.13.93.50 DST=8.8.8.8 PROTO=UDP DPT=999";
                  };
                }
                {
                  insert_at = "filter_redirect_logs";
                  type = "log";
                  log_fields = {
                    SYSLOG_FACILITY = LOCAL2;
                    not_message = "malformed event";
                  };
                }
              ];
              no_outputs_from = [
                "parse_dns_redirect"
                "parse_ntp_redirect"
              ];
            }
          ];
          sinks = {
            console = {
              type = "console";
              inputs = [ "post_aggregate" ];
              encoding.codec = "json";
            };
            loki = {
              type = "loki";
              inputs = [ "post_aggregate" ];
              encoding.codec = "json";
              encoding.only_fields = [
                "message"
                "value"
              ];
              inherit (cfg.loki) endpoint;
              labels = {
                app = "router";
                netlog = "{{ prefix }}";
              };
            };
            loki_dns = {
              type = "loki";
              inputs = [ "parse_dns_redirect" ];
              encoding.codec = "json";
              encoding.only_fields = [
                "src"
                "dst"
                "iface"
              ];
              inherit (cfg.loki) endpoint;
              labels = {
                app = "router";
                netlog = "dns-redirect";
              };
            };
            loki_ntp = {
              type = "loki";
              inputs = [ "parse_ntp_redirect" ];
              encoding.codec = "json";
              encoding.only_fields = [
                "src"
                "dst"
                "iface"
              ];
              inherit (cfg.loki) endpoint;
              labels = {
                app = "router";
                netlog = "ntp-redirect";
              };
            };
            loki_encrypted_dns = {
              type = "loki";
              inputs = [ "parse_encrypted_dns" ];
              encoding.codec = "json";
              encoding.only_fields = [
                "src"
                "dst"
                "dpt"
                "iface"
              ];
              inherit (cfg.loki) endpoint;
              labels = {
                app = "router";
                netlog = "encrypted-dns";
              };
            };
          };
        };
      };
    };
  };
}
