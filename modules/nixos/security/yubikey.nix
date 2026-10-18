{
  flake.modules.nixos.yubikey =
    # System support for YubiKey/SmartCard (pcscd) and FIDO2/U2F auth.
    #
    # PC/SC (smartcard access) is always on, independent of FIDO2/U2F. The
    # Secret Service (oo7) lives in desktop/secret-service.nix. The pam_u2f
    # module (security.pam.u2f) follows security.fido2Auth.enable, on by
    # default: pam_u2f is "sufficient" and fails at once without an enrolled
    # key plugged in, so the password still works. Which services use it, and
    # in what order, is in security/pam-policy.nix.
    {
      config,
      lib,
      pkgs,
      ...
    }:

    let
      cfg = config.security.fido2Auth;
      wheelUsers = lib.attrNames (
        lib.filterAttrs (
          _name: user: (user.isNormalUser or false) && lib.elem "wheel" (user.extraGroups or [ ])
        ) config.users.users
      );
    in
    {
      options.security.fido2Auth = {
        enable =
          lib.mkEnableOption ''
            FIDO2/U2F-based PAM and PolKit authentication (pam_u2f, YubiKey touch)
            for sudo, run0, polkit/pkexec and the lock screen (never for login)
          ''
          // {
            default = true;
          };
      };

      config = lib.mkMerge [
        {
          # Always on: PC/SC daemon (YubiKey PIV/OpenPGP, smartcards) —
          # unrelated to FIDO2/U2F.
          services.pcscd.enable = true;

          security.pam.services = {
            # run0 (systemd): authenticate once and remember for 5 minutes (pam_timestamp).
            # Order: timestamp (400) → fingerprint (500) → pam_u2f → password.
            # auth:    reads /run/pam_timestamp/<user>/run0:<tty>; if recent (< 5 min),
            #          returns success without re-authenticating.
            # session: writes the timestamp after a successful authentication,
            #          resetting the 5-minute window.
            # Note: linux-pam ≥ 1.7 uses /run/pam_timestamp (no longer /run/sudo).
            #       The directory is created via systemd.tmpfiles below.
            run0.rules = {
              auth.timestamp = {
                control = "sufficient";
                modulePath = "${pkgs.linux-pam}/lib/security/pam_timestamp.so";
                order = 400; # Before pam_fprintd (500, security/pam-policy.nix)
              };
              session.timestamp = {
                control = "optional";
                modulePath = "${pkgs.linux-pam}/lib/security/pam_timestamp.so";
                order = 500;
              };
            };
          };

          # pam_timestamp's timestamp directory (linux-pam ≥ 1.7).
          # pam_timestamp doesn't create the parent directory — without it, the
          # session module fails silently (control "optional") and the cache is
          # never written.
          systemd.tmpfiles.rules = [
            "d /run/pam_timestamp 0700 root root -"
            "d /run/sudo          0700 root root -" # sudo compatibility
          ];
        }

        (lib.mkIf cfg.enable {
          # Enables the U2F PAM module (pam_u2f) for YubiKey authentication.
          security.pam.u2f = {
            enable = true;
            settings = {
              cue = true;
              # interactive deliberately omitted: without this flag, pam_u2f
              # doesn't require "press Enter" via TTY before waiting for the key
              # touch. This lets GNOME's polkit agent (built into gnome-shell)
              # show the graphical auth dialog — the user inserts the YubiKey and
              # touches the key without needing to interact with a terminal.
              authfile = "/persist/etc/u2f-mappings";
            };
          };

          # Every PAM service gets pam_u2f by default (security.pam.u2f.enable);
          # security/pam-policy.nix takes it off login and greetd.

          # Automatic check on switch/rebuild to avoid a sudo lockout.
          system.activationScripts.checkPamU2FMapping = {
            deps = [ "users" ];
            text = ''
              authfile="/persist/etc/u2f-mappings"

              if [ ! -f "$authfile" ]; then
                echo "WARNING: $authfile does not exist. sudo with YubiKey (pam_u2f) will fail." >&2
              else
                for user in ${lib.concatStringsSep " " (map lib.escapeShellArg wheelUsers)}; do
                  if ! grep -q "^${"$"}user:" "$authfile"; then
                    echo "WARNING: $authfile has no entry for '${"$"}user' (wheel group)." >&2
                  fi
                done
              fi
            '';
          };
        })
      ];
    };
}
