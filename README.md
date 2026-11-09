# nix-framework-fingerprint-led-blink

NixOS flake for [alejandroqh/framework-fingerprint-led-blink](https://github.com/alejandroqh/framework-fingerprint-led-blink):
blink the **power-button LED** of a Framework laptop while fprintd waits for
your finger (sudo, login, lock screen, polkit, enroll).

On the Framework 16 the fingerprint reader is inside the power button, but
nothing tells you when it actually expects a touch. Upstream's small service
subscribes to fprintd's own signals (`gdbus monitor --dest net.reactivated.Fprint`,
sender verified by the bus) and blinks `/sys/class/leds/chromeos:white:power`
while fprintd's `finger-needed` property is `true`, with a 60 s safety timeout.
The LED is always handed back to the EC (`chromeos-auto` trigger). See upstream
for the demo and details.

This repo does not carry a copy of the script. It pulls upstream as a pinned
flake input and:

- packages it (`patchShebangs` for python, absolute `gdbus` path)
- turns upstream's tunable constants into override parameters / module options
- ships a NixOS module with an unprivileged, hardened systemd unit
  (`DynamicUser` in group `fprint-led`, no capabilities, private
  network/devices, read-only system, syscall filter) plus a udev rule that lets
  that group write only the LED's `trigger` and `brightness`

Tested on a Framework Laptop 16 (Ryzen 9 7940HS, Goodix `27c6:609c`), NixOS
unstable, kernel 7.3.

## Usage

```nix
# flake.nix
inputs.nix-framework-fingerprint-led-blink = {
  url = "github:sophronesis/nix-framework-fingerprint-led-blink";
  inputs.nixpkgs.follows = "nixpkgs";
};

# in nixosSystem modules
imports = [ inputs.nix-framework-fingerprint-led-blink.nixosModules.default ];
services.framework-fingerprint-led-blink.enable = true;
```

The module also sets `services.fprintd.enable = mkDefault true`. The package
is built against your system `pkgs`, not this flake's nixpkgs pin.

Nothing blinks until fprintd actually asks for a finger: enroll one with
`fprintd-enroll`, and make sure the PAM service you care about has
`security.pam.services.<name>.fprintAuth` on (it defaults to
`services.fprintd.enable`).

### Options

| option | default | |
|---|---|---|
| `enable` | `false` | |
| `led` | `"chromeos:white:power"` | name under `/sys/class/leds`; falls back to `chromeos:multicolor:power` (older FW13) if missing |
| `onSeconds` | `0.25` | |
| `offSeconds` | `0.25` | |
| `maxBlinkSeconds` | `60` | safety net if a stop signal is missed |
| `package` | built from upstream | gets `.override`n with the four above |

All under `services.framework-fingerprint-led-blink`.

### Package only

```nix
nixpkgs.overlays = [ inputs.nix-framework-fingerprint-led-blink.overlays.default ];

pkgs.framework-fingerprint-led-blink.override {
  onSeconds = 0.1;
  offSeconds = 0.4;
}
```

or `nix build github:sophronesis/nix-framework-fingerprint-led-blink`.

## Testing

The watcher only reacts to fprintd's own `finger-needed` property, so it needs
a real prompt (an unclaimed `VerifyStart` no longer makes it blink):

```bash
sudo -k; sudo true   # watch the power button before touching the sensor
```

Check that it runs unprivileged and the udev rule applied:

```bash
systemctl show -p User,MainPID framework-fingerprint-led-blink
ls -lL /sys/class/leds/chromeos:white:power/{trigger,brightness}   # root fprint-led, rw-rw-r--
systemd-analyze security framework-fingerprint-led-blink
```

## Troubleshooting

```bash
systemctl status framework-fingerprint-led-blink
journalctl -u framework-fingerprint-led-blink -b
```

Stuck LED:

```bash
echo chromeos-auto | sudo tee /sys/class/leds/chromeos:white:power/trigger
```

## Updating

```bash
nix flake update upstream
nix flake check
```

Every substitution in `package.nix` uses `--replace-fail`, so if upstream
changes one of the patched lines the build breaks instead of silently dropping
a setting.

## License

Nix code here: MIT, see [LICENSE](LICENSE). Upstream script: Apache-2.0.
