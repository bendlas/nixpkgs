let
  tests = {
    wayland =
      { pkgs, ... }:
      {
        imports = [ ./common/wayland-cage.nix ];

        # We scale void-editor to help OCR find the small "Untitled" text.
        services.cage.program = "${pkgs.void-editor}/bin/void --force-device-scale-factor=2";

        environment.variables.NIXOS_OZONE_WL = "1";
        environment.variables.DISPLAY = "do not use";

        fonts.packages = with pkgs; [ dejavu_fonts ];
      };
    xorg =
      { pkgs, ... }:
      {
        imports = [
          ./common/user-account.nix
          ./common/x11.nix
        ];

        virtualisation.memorySize = 2047;
        services.xserver.enable = true;
        services.xserver.displayManager.sessionCommands = ''
          ${pkgs.void-editor}/bin/void --force-device-scale-factor=2
        '';
        test-support.displayManager.auto.user = "alice";
      };
  };

  mkTest =
    name: machine:
    import ./make-test-python.nix (
      { pkgs, ... }:
      {
        inherit name;

        nodes = {
          "${name}" = machine;
        };

        enableOCR = true;

        testScript = ''
          @polling_condition
          def void_running():
              machine.succeed('pgrep -x void')


          start_all()

          machine.wait_for_unit('graphical.target')

          void_running.wait() # type: ignore[union-attr]
          with void_running: # type: ignore[union-attr]
              # Wait until void is visible. "File" is in the menu bar.
              machine.wait_for_text('Get Started with')
              machine.screenshot('start_screen')

              test_string = 'testfile'

              # Create a new file
              machine.send_key('ctrl-n')
              machine.wait_for_text('Untitled')
              machine.screenshot('empty_editor')

              # Type a string
              machine.send_chars(test_string)
              machine.wait_for_text(test_string)
              machine.screenshot('editor')

              # Save the file
              machine.send_key('ctrl-s')
              machine.wait_for_text('(Save|Desktop|alice|Size)')
              machine.screenshot('save_window')
              machine.send_key('ret')

              # (the default filename is the first line of the file)
              machine.wait_for_file(f'/home/alice/{test_string}')

          # machine.send_key('ctrl-q')
          # machine.wait_until_fails('pgrep -x codium')
        '';
      }
    );

in
builtins.mapAttrs (k: v: mkTest k v) tests
