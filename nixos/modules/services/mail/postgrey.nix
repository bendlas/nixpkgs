{ config, lib, pkgs, ... }:

with lib; let

  cfg = config.services.postgrey;

in {

  options = {
    services.postgrey = {
      enable = mkOption {
        default = false;
        description = "Whether to run the Postgrey daemon";
      };
      inetAddr = mkOption {
        default = null;
        example = "127.0.0.1";
        description = "The ip address to bind to";
      };
      inetPort = mkOption {
        default = 10030;
        description = "The tcp port to bind to";
      };
      greylistText = mkOption {
        default = "Greylisted for %%s seconds";
        description = "Response status text for greylisted messages";
      };
    };
  };

  config = mkIf cfg.enable {

    environment.systemPackages = [ pkgs.postgrey ];

    users = {
      extraUsers = {
        postgrey = {
          description = "Postgrey Daemon";
          uid = config.ids.uids.postgrey;
          group = "postgrey";
        };
      };
      extraGroups = {
        postgrey = {
          gid = config.ids.gids.postgrey;
        };
      };
    };

    systemd.services.postgrey = let
      bind-flag = if isNull cfg.inetAddr then
        "--unix=/var/run/postgrey.sock"
      else
        "--inet=${cfg.inetAddr}:${cfg.inetPort}";
    in {
      description = "Postfix Greylisting Service";
      wantedBy = [ "multi-user.target" ];
      before = [ "postfix.service" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = ''${pkgs.postgrey}/bin/postgrey ${bind-flag} --pidfile=/var/run/postgrey.pid --group=postgrey --user=postgrey --greylist-text="${cfg.greylistText}"'';
        Restart = "always";
        RestartSec = 5;
        TimeoutSec = 10;
      };
    };

  };

}
