    # nixosConfigurations.machine = nixpkgs.lib.nixosSystem {
    #   # Note that you cannot put arbitrary configuration here: the configuration must be placed in the files loaded via modules
    #   system = "x86_64-linux";
    #   modules = [
    #     (nixpkgs + "/nixos/modules/<some-module>.nix")
    #     ./machine.nix
    #   ];
    # };

{
  outputs = { self, nixpkgs }: {
    nixosConfigurations.test-container = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [({ pkgs, ... }: {
        system.stateVersion = "25.11";
        boot.isContainer = true;
        boot.isNspawnContainer = true;
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
            echo "Attempting to read from host's netcat server..."
            response=$(echo | ${pkgs.netcat}/bin/nc -w1 192.168.100.1 8080)
            if [ "$response" = "READY" ]; then
              echo "Successfully read from host! Container networking is up."
            else
              echo "Failed to read from host. Retrying..."
              exit 1
            fi
          '';
        };
      })];
    };
  };
}
