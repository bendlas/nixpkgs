{ config, lib, pkgs, ... }:

with lib;

let

  dmcfg = config.services.xserver.displayManager;

  cfg = dmcfg.qingy;

  ## set dirs up before other config
  qingyConfigDirs = {
    screensavers_dir = "${pkgs.qingy}/lib/qingy/screensavers";
    temp_files_dir = "/var/tmp";
    themes_dir = "${pkgs.qingy}/share/qingy/themes";
    text_sessions = "/etc/qingy/sessions/";
  };

  qingyConfig = {
    # see qingy package /etc
    x_sessions = toString dmcfg.session.desktops;
    xinit = dmcfg.xserverBin;
    x_args = dmcfg.xserverArgs;
    log_level = enum "error";
    log_facilities = enum "console";
    x_server_tty = enum "qingy_tty";
    screensaver_timeout = 5;
    screen_powersaving_timeout = 30;
    theme = "default";
    shutdown_policy = enum "everyone";
    last_user_policy = enum "global";
    last_session_policy = enum "user";
    sleep = "${pkgs.pmutils}/bin/pm-suspend-hybrid";
  };

  enum = v: { inherit v; __toString = v: v.v; };

  renderConfig = sep: cfg: ''
    ${lib.concatStringsSep sep (
      lib.mapAttrsToList (
        k: v: "${k} = ${if lib.isString v
          then "\"${v}\""
          else toString v}"
      ) cfg)}
  '';
in

{

  ###### interface

  options = {

    services.xserver.displayManager.qingy = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to enable QingY as the display manager.
        '';
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Extra configuration options for QingY login manager. Do not
          add options that can be configured directly.
        '';
      };

    };

  };


  ###### implementation

  config = mkIf cfg.enable {

    services.xserver.displayManager.job =
      {
        execCmd = "true";
      };


/*    systemd.services."getty@" = {
      serviceConfig.ExecStart = lib.mkForce "@${pkgs.qingy}/bin/qingy %I";
    }; */

    services.xserver.displayManager.slim.enable = false;

    systemd.units."qingy@.service".text = ''
      [Unit]
      Description="QingY getty / X display manager"
      After=systemd-user-sessions.service
      After=systemd-logind.service
      After=systemd-vconsole-setup.service
      Requires=systemd-logind.service
      Before=getty.target
      Conflicts=getty@%i.service
      OnFailure=getty@%i.service
      IgnoreOnIsolate=yes
      ConditionPathExists=/dev/tty0

      [Service]
      Type=idle
      ExecStart=${pkgs.qingy}/bin/qingy %I
      UtmpIdentifier=%I
      TTYPath=/dev/%I
      TTYReset=yes
      TTYVTDisallocate=yes
    '';

    systemd.units."autovt@.service".unit = pkgs.runCommand "unit" { } ''
      mkdir -p $out
      ln -s ${config.systemd.units."qingy@.service".unit}/qingy@.service $out/autovt@.service
    '';

    environment = {
      systemPackages = [ pkgs.qingy ];
      etc."qingy/settings".source = pkgs.writeText "qingy.cfg" ''
       ${renderConfig "\n" qingyConfigDirs}
       ${renderConfig "\n" qingyConfig}
       screensaver "running_time"
       #keybindings
       #{
       #   prev_tty    = "ALT-left"      # switch to left tty
       #   next_tty    = "ALT-right"     # switch to right tty
       #   poweroff    = "CTRL-ALT-p"    # shutdown your system
       #   reboot      = "CTRL-ALT-r"    # restart your system
       #   screensaver = "CTRL-ALT-s"    # activate screen saver
       #   sleep       = "CTRL-ALT-z"    # put machine to sleep
       #   kill        = "CTRL-ALT-backspace"   # kill qingy
       #   text_mode   = "CTRL-ESC" # Revert to text mode
       #}
       ${cfg.extraConfig}
      '';
    };

  };

}
