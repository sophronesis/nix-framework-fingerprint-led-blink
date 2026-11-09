# alejandroqh/framework-fingerprint-led-blink, packaged for nix.
#
# upstream is one stdlib-only python script whose tunables are module-level
# constants. they are exposed as override parameters here (the nixos module
# maps its options onto them), so no editing:
#
#   framework-fingerprint-led-blink.override {
#     onSeconds = 0.1;
#     offSeconds = 0.4;
#     maxBlinkSeconds = 30;
#   }
#
# every substitution uses --replace-fail, so an upstream change to any of these
# lines breaks the build instead of silently dropping a setting.
{
  lib,
  stdenvNoCC,
  python3,
  glib,
  # pinned upstream source, set from the flake input
  src,
  version,
  # led under /sys/class/leds. chromeos:white:power is the power button (and
  # fingerprint reader) on the framework 16, exposed by leds_cros_ec
  led ? "chromeos:white:power",
  onSeconds ? 0.25,
  offSeconds ? 0.25,
  # safety net: never blink longer than this, even if finger-needed never turns false
  maxBlinkSeconds ? 60,
}:

stdenvNoCC.mkDerivation {
  pname = "framework-fingerprint-led-blink";
  inherit src version;

  __structuredAttrs = true;
  strictDeps = true;

  # host python, so patchShebangs rewrites `#!/usr/bin/python3 -I`
  buildInputs = [ python3 ];

  dontConfigure = true;
  dontBuild = true;

  postPatch = ''
    substituteInPlace framework-fingerprint-led-blink \
      --replace-fail 'LED = "/sys/class/leds/chromeos:white:power"' \
                     'LED = "/sys/class/leds/${led}"' \
      --replace-fail 'ON_S, OFF_S = 0.25, 0.25' \
                     'ON_S, OFF_S = ${toString onSeconds}, ${toString offSeconds}' \
      --replace-fail 'MAX_BLINK_S = 60' \
                     'MAX_BLINK_S = ${toString maxBlinkSeconds}' \
      --replace-fail '["gdbus",' \
                     '["${lib.getExe' glib "gdbus"}",'
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 framework-fingerprint-led-blink -t $out/bin
    runHook postInstall
  '';

  meta = {
    description = "Blink the Framework laptop power-button LED while fprintd waits for a finger";
    homepage = "https://github.com/alejandroqh/framework-fingerprint-led-blink";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "framework-fingerprint-led-blink";
  };
}
