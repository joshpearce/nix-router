_: {
  config = {
    systemd = {
      services = {

        network-irq-affinity = {
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          requires = [ "network-online.target" ];
          description = "Keep hardware interrupts and RPS on different cores";
          serviceConfig = {
            Type = "simple";
          };
          script = ''

            smp1=1 # 0x00000001, restrict to CPU 0
            rps1=2 # 0x00000010, restrict to CPU 1
            smp2=1 # 0x00000001, restrict to CPU 0
            rps2=2 # 0x00000010, restrict to CPU 1

            # set balancer for enp1s0
            echo "$smp1" > /proc/irq/49/smp_affinity
            echo "$smp1" > /proc/irq/50/smp_affinity
            echo "$smp1" > /proc/irq/51/smp_affinity
            echo "$smp1" > /proc/irq/52/smp_affinity
            echo "$smp1" > /proc/irq/53/smp_affinity

            # set rps for enp1s0
            echo "$rps1" > /sys/class/net/enp1s0/queues/rx-0/rps_cpus
            echo "$rps1" > /sys/class/net/enp1s0/queues/rx-1/rps_cpus

            # set balancer for enp2s0
            echo "$smp2" > /proc/irq/54/smp_affinity
            echo "$smp2" > /proc/irq/55/smp_affinity
            echo "$smp2" > /proc/irq/56/smp_affinity
            echo "$smp2" > /proc/irq/57/smp_affinity
            echo "$smp2" > /proc/irq/58/smp_affinity

            # set rps for enp2s0
            echo "$rps2" > /sys/class/net/enp2s0/queues/rx-0/rps_cpus
            echo "$rps2" > /sys/class/net/enp2s0/queues/rx-1/rps_cpus
          '';
        };

      };
    };
  };
}
