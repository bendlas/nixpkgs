{ pkgs, lib, ... }:
{
  name = "containers-networking-startup";
  meta = {
    maintainers = with lib.maintainers; [ ];
  };

  nodes.machine =
    { pkgs, ... }:
    {
      # virtualisation.writableStore = true;
      networking.firewall.allowedTCPPorts = [ 8080 ];

      # Run netcat listener on the host
      systemd.services.netcat-server = {
        description = "Netcat server for container networking test";
        wantedBy = [ "multi-user.target" ];
        before = [ "container@test-container.service" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.bash}/bin/bash -c 'while true; do echo \"READY\" | ${pkgs.netcat}/bin/nc -l 8080; done'";
          Restart = "always";
        };
      };

      # environment.systemPackages = [ pkgs.nixos-containers ];
      boot.enableContainers = true;

      nix.extraOptions = ''
        experimental-features = nix-command flakes
      '';


      # # Define a declarative container
      # containers.test-container = {
      #   autoStart = true;
      #   privateNetwork = true;
      #   hostAddress = "192.168.100.1";
      #   localAddress = "192.168.100.2";
        
      #   config = { pkgs, ... }: {
      #     # Oneshot service that retries connecting to host's netcat
      #     systemd.services.network-check = {
      #       description = "Check container networking is available";
      #       wantedBy = [ "multi-user.target" ];
      #       before = [ "multi-user.target" ];
      #       after = [ "network.target" ];
            
      #       serviceConfig = {
      #         Type = "oneshot";
      #         RemainAfterExit = true;
      #         Restart = "on-failure";
      #         RestartSec = "1s";
      #         StartLimitBurst = 30;
      #       };
            
      #       script = ''
      #         echo "Attempting to read from host's netcat server..."
      #         response=$(echo | ${pkgs.netcat}/bin/nc -w1 192.168.100.1 8080)
      #         if [ "$response" = "READY" ]; then
      #           echo "Successfully read from host! Container networking is up."
      #         else
      #           echo "Failed to read from host. Retrying..."
      #           exit 1
      #         fi
      #       '';
      #     };
      #   };
      # };

    };

  # testScript = ''
  #   machine.start()
  #   machine.wait_for_unit("default.target")
    
  #   with subtest("Ensure netcat server is running on host"):
  #       machine.wait_for_unit("netcat-server.service")
  #       machine.succeed("pgrep -f 'nc -l 8080'")
    
  #   with subtest("Container starts and network-check service succeeds"):
  #       # The container should start automatically due to autoStart = true
  #       machine.wait_for_unit("container@test-container.service")
        
  #       # Wait for the network-check service to succeed inside the container
  #       # This proves that networking became available during container startup
  #       machine.succeed("nixos-container run test-container -- systemctl is-active network-check.service")
        
  #       # Verify the service is marked as successful
  #       machine.succeed("nixos-container run test-container -- systemctl status network-check.service")
    
  #   with subtest("Verify container can communicate with host"):
  #       # Double-check that the container can actually reach the host and read data
  #       result = machine.succeed("nixos-container run test-container -- sh -c 'echo | nc -w1 192.168.100.1 8080'")
  #       assert "READY" in result, f"Expected 'READY' in response but got: {result}"
  # '';

  testScript = ''
    machine.start()
    machine.wait_for_unit("default.target")
    
    with subtest("Container starts and network-check service succeeds"):
        # Wait for the network-check service to succeed inside the container
        # This proves that networking became available during container startup
        machine.copy_from_host("${./container-networking-startup}", "/tmp/test")
        machine.succeed("nixos-container create --flake /tmp/test#test-container --host-address 192.168.100.1 --local-address 192.168.100.2 test")
        machine.wait_for_unit("container@test.service")
  '';

}
