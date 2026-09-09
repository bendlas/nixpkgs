# This module builds a tool, `install-to-mounted-root`, that populates an
# already-prepared and mounted set of partitions with the NixOS system being
# built, so that the result boots -- without writing a disk image and without
# running any target-architecture binaries on the build host.
#
# It fills the same niche as `nixos-install` / `nixos-enter` (write to a
# mounted `--root`), but unlike `nixos-install` it is safe to use
# cross-architecture (e.g. install an aarch64 system from an x86_64 host):
# the store is populated with host `nix --store`, and the boot loader is
# installed with build-architecture tooling only.
#
# For the boot loader it supports:
#   * `boot.loader.generic-extlinux-compatible` (e.g. U-Boot), installed with
#     that module's build-architecture `populateCmd`;
#   * `boot.loader.systemd-boot`, installed to a mounted EFI System Partition
#     by copying the target-arch `systemd-boot<arch>.efi` to the UEFI fallback
#     path (`EFI/BOOT/BOOT<ARCH>.EFI`) and writing a single Boot Loader
#     Specification entry from the toplevel bootspec.  No EFI variables are
#     touched, which is what you want for removable media (USB sticks, SD
#     cards) and is mandatory for cross-architecture installs; and
#   * `boot.loader.grub`, installed with the build host's GRUB utilities only
#     (`grub-mkimage` for EFI removable media, `grub-install` for BIOS/MBR).
#     Cross-architecture GRUB install requires the GRUB utilities to run on the
#     build host; for an aarch64 target built from x86_64 that means a
#     host-runnable GRUB that emits aarch64 firmware, which nixpkgs does not
#     expose by default -- so GRUB works out of the box for same-architecture
#     installs, and needs a host-runnable GRUB for the target firmware in the
#     cross case.
#
# Two build attributes are produced, both pointing at the *same* combined
# package (so the password tool ships alongside the installer):
#   * `system.build.installToMountedRoot` -- register the store *immediately*
#     with host `nix --store` (like `nixos-install`).  Default and recommended.
#   * `system.build.installToMountedRootFileReg` -- copy the closure with `cp`
#     and write `/nix-path-registration`; the store is registered on first boot
#     by the `register-nix-paths` service (enabled with
#     {option}`mountedInstall.registerOnFirstBoot`).  Useful when `nix
#     --store` against the target is unavailable.
#
# The combined package also contains `bin/set-mounted-root-password`, a
# cross-architecture-safe tool that writes a password hash into the mounted
# root's `/etc/shadow` (only hashing runs on the build host).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  bpkgs = pkgs.buildPackages;

  toplevel = config.system.build.toplevel;

  # Closure metadata for the file-registration mode.  Computed once; only
  # physically used by the file-registration installer.
  closureInfo = bpkgs.closureInfo { rootPaths = [ toplevel ]; };

  # Which boot loader this configuration is set up for.
  defaultBootloader =
    if config.boot.loader.generic-extlinux-compatible.enable then
      "extlinux"
    else if config.boot.loader.systemd-boot.enable then
      "systemd-boot"
    else if config.boot.loader.grub.enable then
      "grub"
    else
      "none";

  # GRUB (cross-architecture safe: only the build host's grub utilities run).
  # grub.nix does not expose its GRUB package derivations under
  # config.boot.loader.grub (it only feeds them to install-grub.pl), and it
  # defaults the exposed system.build.grub to a non-EFI build, so we build a
  # host-runnable GRUB directly here.  For EFI we need the EFI-enabled build so
  # grub-mkimage has the target's EFI core modules.
  cfg = config.boot.loader.grub;
  grubEnabled = cfg.enable;
  grubEfiSupport = cfg.efiSupport;
  grubPkg =
    if grubEfiSupport then bpkgs.grub2.override { efiSupport = true; }
    else bpkgs.grub2;
  # When GRUB is disabled this derivation is never executed (the chosen boot
  # loader will not be GRUB), so the fallback is just a build-host GRUB.
  grubTool = if grubEnabled then grubPkg else bpkgs.grub2;
  grubPlatform =
    if grubEnabled then grubPkg.grubTarget
    else "${pkgs.stdenv.hostPlatform.efiArch}-efi";
  grubEsp = lib.removePrefix "/" config.boot.loader.efi.efiSysMountPoint;
  grubBootDir =
    let
      boots = cfg.mirroredBoots;
    in
    if boots != [ ] then
      lib.removePrefix "/" (builtins.head boots).path
    else
      "boot";
  grubRemovable = if cfg.efiInstallAsRemovable then "1" else "0";
  grubDevice =
    let
      boots = cfg.mirroredBoots;
    in
    if boots != [ ] && (builtins.head boots).devices != [ ] then
      builtins.head (builtins.head boots).devices
    else
      "";
  grubDistroName = config.system.nixos.distroName;
  grubDistroId = lib.toLower grubDistroName;
  grubInstaller = bpkgs.replaceVarsWith {
    name = "grub-install-to-mounted";
    src = ./grub-install-to-mounted.sh;
    dir = "bin";
    isExecutable = true;
    replacements = {
      runtimeShell = bpkgs.runtimeShell;
      grubTool = grubTool;
      grubPlatform = grubPlatform;
      grubEsp = grubEsp;
      grubBootDir = grubBootDir;
      distroName = grubDistroName;
      distroId = grubDistroId;
      blkid = bpkgs.util-linux;
    };
  };

  # Paths relative to the target root.
  defaultEsp = lib.removePrefix "/" config.boot.loader.efi.efiSysMountPoint;
  defaultBootDir =
    let
      boots = config.boot.loader.generic-extlinux-compatible.mirroredBoots;
    in
    if boots != [ ] then
      lib.removePrefix "/" (builtins.head boots).path
    else
      "boot";

  extlinuxPopulateCmd = config.boot.loader.generic-extlinux-compatible.populateCmd;

  # systemd-boot removable-media installer (build-architecture helper).
  systemdBootRemovable = bpkgs.replaceVarsWith {
    name = "systemd-boot-removable";
    src = ./systemd-boot-removable.py;
    dir = "bin";
    isExecutable = true;
    replacements = {
      python3 = bpkgs.python3;
      efiArch = pkgs.stdenv.hostPlatform.efiArch;
      systemd = config.systemd.package;
      distroName = config.system.nixos.distroName;
      storeDir = builtins.storeDir;
    };
  };

  systemdBootTimeout =
    if config.boot.loader.timeout == null then
      "menu-force"
    else
      toString config.boot.loader.timeout;
  systemdBootEditor = if config.boot.loader.systemd-boot.editor then "1" else "0";
  systemdBootConsoleMode = config.boot.loader.systemd-boot.consoleMode;

  # Build the installer script for a given registration `mode` ("immediate" or
  # "file").  Both are the same template, baked with different defaults so that
  # users get two distinct, self-documenting targets.
  mkInstaller =
    mode:
    bpkgs.replaceVarsWith {
      name =
        if mode == "file" then
          "install-to-mounted-root-file-reg"
        else
          "install-to-mounted-root";
      src = ./install-to-mounted-root.sh;
      dir = "bin";
      isExecutable = true;
      replacements = {
        runtimeShell = bpkgs.runtimeShell;
        path = lib.makeBinPath [
          bpkgs.nix
          bpkgs.coreutils
          bpkgs.findutils
          bpkgs.gnused
          bpkgs.gnugrep
        ];
        defaultSystem = toplevel;
        inherit defaultBootloader;
        inherit defaultEsp;
        inherit defaultBootDir;
        fileRegistration = if mode == "file" then "1" else "0";
        storePathsFile =
          if mode == "file" then "${closureInfo}/store-paths" else "/dev/null";
        registrationFile =
          if mode == "file" then "${closureInfo}/registration" else "/dev/null";
        extlinuxPopulateCmd =
          if config.boot.loader.generic-extlinux-compatible.enable then
            extlinuxPopulateCmd
          else
            "true";
        systemdBootRemovable = "${systemdBootRemovable}/bin/systemd-boot-removable";
        systemdBootTimeout = systemdBootTimeout;
        systemdBootEditor = systemdBootEditor;
        systemdBootConsoleMode = systemdBootConsoleMode;
        grubInstaller = "${grubInstaller}/bin/grub-install-to-mounted";
        grubPlatform = grubPlatform;
        grubRemovable = grubRemovable;
        grubDevice = grubDevice;
      };
    };

  installerImmediate = mkInstaller "immediate";
  installerFileReg = mkInstaller "file";
  passwordTool = bpkgs.replaceVarsWith {
    name = "set-mounted-root-password";
    src = ./set-mounted-root-password.sh;
    dir = "bin";
    isExecutable = true;
    replacements = {
      mkpasswd = bpkgs.mkpasswd;
      runtimeShell = bpkgs.runtimeShell;
    };
  };
  # Combined package: both installer modes plus the password tool share one
  # output, so they can be shipped and run together on the (possibly foreign)
  # architecture host.
  mountedInstall = bpkgs.symlinkJoin {
    name = "mounted-install";
    paths = [ installerImmediate installerFileReg passwordTool ];
  };

  nixPathRegistrationFile = config.mountedInstall.nixPathRegistrationFile;
in
{
  options.mountedInstall = {
    registerOnFirstBoot = lib.mkEnableOption ''
      a one-shot first-boot service that registers the Nix store from
      {file}`/nix-path-registration` (the value of
      {option}`mountedInstall.nixPathRegistrationFile`) and sets the
      system profile.

      This is required when the system is installed with
      {command}`install-to-mounted-root-file-reg` (the file-registration
      mode), which copies the closure with `cp` and writes the registration
      file but does not register it.  The immediate mode
      ({command}`install-to-mounted-root`) registers with host `nix --store`
      and does not need this service.
    '';

    nixPathRegistrationFile = lib.mkOption {
      type = lib.types.str;
      default = "/nix-path-registration";
      description = ''
        Location of the file containing the input for `nix-store --load-db`
        on first boot.  Only relevant when
        {option}`mountedInstall.registerOnFirstBoot` is enabled.
      '';
    };
  };

  config = {
    system.build = {
      # Both installer modes point at the same combined package, which also
      # contains the password-setting tool (bin/set-mounted-root-password).
      installToMountedRoot = mountedInstall;
      installToMountedRootFileReg = mountedInstall;
    };

    systemd.services.register-nix-paths = lib.mkIf config.mountedInstall.registerOnFirstBoot {
      description = "Register Nix Store Paths";
      unitConfig = {
        DefaultDependencies = false;
        ConditionPathExists = nixPathRegistrationFile;
      };
      wantedBy = [ "sysinit.target" ];
      before = [
        "sysinit.target"
        "shutdown.target"
        "nix-daemon.socket"
        "nix-daemon.service"
      ];
      after = [ "local-fs.target" ];
      conflicts = [ "shutdown.target" ];
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${lib.getExe' config.nix.package.out "nix-store"} --load-db < ${nixPathRegistrationFile}

        # nixos-rebuild also requires a "system" profile and an /etc/NIXOS tag.
        touch /etc/NIXOS
        ${lib.getExe' config.nix.package.out "nix-env"} -p /nix/var/nix/profiles/system --set /run/current-system

        # Prevents this from running on later boots.
        rm -f ${nixPathRegistrationFile}
      '';
    };
  };
}
