{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.xserver.windowManager.exwm;
  loadScript = pkgs.writeText "emacs-exwm-load" ''
    ${cfg.loadScript}
  '';
  packages = epkgs: cfg.extraPackages epkgs ++ [ epkgs.exwm ];
in
{

  imports = [
    (mkRemovedOptionModule [ "services" "xserver" "windowManager" "exwm" "enableDefaultConfig" ]
      "The upstream EXWM project no longer provides a default configuration, instead copy (parts of) exwm-config.el to your local config."
    )
  ];

  options = {
    services.xserver.windowManager.exwm = {
      enable = mkEnableOption "exwm";
      emacsPkg = mkOption {
        type = types.package;
        default = pkgs.emacs.pkgs.withPackages packages;
        defaultText = "pkgs.emacs.pkgs.withPackages (...)";
        description = ''
          EXWM emacs package
        '';
      };
      loadScript = mkOption {
        default = "(require 'exwm)";
        type = types.lines;
        example = ''
          (require 'exwm)
          (exwm-enable)
        '';
        description = ''
          Emacs lisp code to be run after loading the user's init
          file.
        '';
      };
      package = mkPackageOption pkgs "Emacs" {
        default = "emacs";
        example = [ "emacs-gtk" ];
      };
      extraPackages = mkOption {
        type = types.functionTo (types.listOf types.package);
        default = epkgs: [ ];
        defaultText = literalExpression "epkgs: []";
        example = literalExpression ''
          epkgs: [
            epkgs.emms
            epkgs.magit
            epkgs.proofgeneral
          ]
        '';
        description = ''
          Extra packages available to Emacs. The value must be a
          function which receives the attrset defined in
          {var}`emacs.pkgs` as the sole argument.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    services.xserver.windowManager.session = singleton {
      name = "exwm";
      start = ''
        ${cfg.emacsPkg}/bin/emacs -l ${loadScript}
      '';
    };
    environment.systemPackages = [ cfg.emacsPkg ];
  };
}
