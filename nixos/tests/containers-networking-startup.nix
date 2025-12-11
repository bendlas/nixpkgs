{ pkgs, lib, ... }:
{
  name = "containers-networking-startup";
  meta = {
    maintainers = with lib.maintainers; [ ];
  };

  nodes.machine =
    { pkgs, ... }:
    {
      virtualisation.writableStore = true;

      # Run netcat listener on the host
      systemd.services.netcat-server = {
        description = "Netcat server for container networking test";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.netcat}/bin/nc -l -p 8080 -k";
          Restart = "always";
        };
      };

      # Define a declarative container
      containers.test-container = {
        autoStart = true;
        privateNetwork = true;
        hostAddress = "192.168.100.1";
        localAddress = "192.168.100.2";
        
        config = { pkgs, ... }: {
          # Oneshot service that retries connecting to host's netcat
          systemd.services.network-check = {
            description = "Check container networking is available";
            wantedBy = [ "multi-user.target" ];
            before = [ "multi-user.target" ];
            after = [ "network.target" ];
            
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              Restart = "on-failure";
              RestartSec = "1s";
              StartLimitBurst = 30;
            };
            
            script = ''
              echo "Attempting to connect to host's netcat server..."
              if ${pkgs.netcat}/bin/nc -z 192.168.100.1 8080; then
                echo "Successfully connected to host! Container networking is up."
              else
                echo "Failed to connect to host. Retrying..."
                exit 1
              fi
            '';
          };
        };
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("default.target")
    
    with subtest("Ensure netcat server is running on host"):
        machine.wait_for_unit("netcat-server.service")
        machine.succeed("pgrep -f 'nc -l -p 8080'")
    
    with subtest("Container starts and network-check service succeeds"):
        # The container should start automatically due to autoStart = true
        machine.wait_for_unit("container@test-container.service")
        
        # Wait for the network-check service to succeed inside the container
        # This proves that networking became available during container startup
        machine.succeed("nixos-container run test-container -- systemctl is-active network-check.service")
        
        # Verify the service is marked as successful
        machine.succeed("nixos-container run test-container -- systemctl status network-check.service")
    
    with subtest("Verify container can communicate with host"):
        # Double-check that the container can actually reach the host
        machine.succeed("nixos-container run test-container -- nc -z 192.168.100.1 8080")
  '';
}
