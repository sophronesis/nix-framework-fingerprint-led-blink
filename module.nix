# nixos module: unprivileged, sandboxed service that blinks the power-button
# led while fprintd waits for a finger (sudo, login, lock screen, polkit,
# enroll). a udev rule lets group fprint-led write only the led's trigger and
# brightness; the service runs as a DynamicUser in that group.
#
#   services.framework-fingerprint-led-blink.enable = true;
#
# `src` and `version` are bound by flake.nix; the default package is built
# against the system's own pkgs, not this flake's nixpkgs pin.
{ src, version }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.framework-fingerprint-led-blink;
  inherit (lib) mkOption types;

  finalPackage = cfg.package.override {
    inherit (cfg)
      led
      onSeconds
      offSeconds
      maxBlinkSeconds
      ;
  };
in
{
  options.services.framework-fingerprint-led-blink = {
    enable = lib.mkEnableOption "blinking the Framework power-button LED while fprintd waits for a finger";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./package.nix { inherit src version; };
      defaultText = lib.literalMD "framework-fingerprint-led-blink built against the system `pkgs`";
      description = ''
        The watcher package. It is `.override`n with `led`, `onSeconds`,
        `offSeconds` and `maxBlinkSeconds`, so a replacement must accept
        those arguments (see package.nix).
      '';
    };

    led = mkOption {
      type = types.str;
      default = "chromeos:white:power";
      example = "chromeos:multicolor:charging";
      description = ''
        LED name under /sys/class/leds. The default is the power button
        (which houses the fingerprint reader) on the Framework 16, exposed
        by the leds_cros_ec driver. If it does not exist, upstream falls back
        to `chromeos:multicolor:power` (older Framework 13, Intel 11th-13th
        gen), lighting only its white channel while blinking. It is handed
        back to the EC with the `chromeos-auto` trigger when blinking stops.
      '';
    };

    onSeconds = mkOption {
      type = types.numbers.positive;
      default = 0.25;
      description = "Seconds the LED stays on per blink.";
    };

    offSeconds = mkOption {
      type = types.numbers.positive;
      default = 0.25;
      description = "Seconds the LED stays off per blink.";
    };

    maxBlinkSeconds = mkOption {
      type = types.numbers.positive;
      default = 60;
      description = "Safety net: stop blinking after this long even if fprintd never reports `finger-needed = false`.";
    };
  };

  config = lib.mkIf cfg.enable {
    # nothing to watch without it
    services.fprintd.enable = lib.mkDefault true;

    # only members may drive the led (see the udev rule below)
    users.groups.fprint-led = { };

    # let group fprint-led write just the trigger, brightness and color
    # intensity of the led, so the watcher runs without root (upstream ships
    # the same rule with /usr/bin paths, which do not exist on nixos).
    # chromeos:multicolor:power is upstream's automatic fallback on older
    # framework 13 (intel 11th-13th gen), which lack chromeos:white:power.
    services.udev.extraRules = ''
      ACTION=="add|change", SUBSYSTEM=="leds", KERNEL=="${cfg.led}|chromeos:multicolor:power", \
        RUN+="${pkgs.coreutils}/bin/chgrp fprint-led /sys%p/trigger /sys%p/brightness /sys%p/multi_intensity", \
        RUN+="${pkgs.coreutils}/bin/chmod g+w /sys%p/trigger /sys%p/brightness /sys%p/multi_intensity"
    '';

    systemd.services.framework-fingerprint-led-blink = {
      description = "Blink power-button LED while fprintd waits for a finger";
      after = [
        "dbus.service"
        "systemd-udevd.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe finalPackage;
        # the script restores the led on SIGTERM itself; this covers SIGKILL
        # and crashes. "-": a missing led must not fail the unit
        # $$ escapes systemd's own variable expansion
        ExecStopPost = "-${pkgs.runtimeShell} -c 'for l in /sys/class/leds/${cfg.led} /sys/class/leds/chromeos:multicolor:power; do [ -w $$l/trigger ] && echo chromeos-auto > $$l/trigger; done; true'";
        Restart = "on-failure";
        RestartSec = 2;

        # unprivileged: upstream now subscribes to fprintd's own signals
        # (`gdbus monitor --dest net.reactivated.Fprint`, sender verified by
        # the bus) instead of eavesdropping with BecomeMonitor, so no root.
        # led write access comes from the fprint-led group (udev rule above).
        DynamicUser = true;
        SupplementaryGroups = [ "fprint-led" ];
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        NoNewPrivileges = true;
        # leaves /sys writable (ProtectKernelTunables would not)
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        # the system bus is a path socket, which survives a private netns
        PrivateNetwork = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        IPAddressDeny = "any";
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged @resources"
        ];
        UMask = "0077";
      };
    };
  };
}
