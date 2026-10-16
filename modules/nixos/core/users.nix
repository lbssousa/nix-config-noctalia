# Contas de usuário (a partir de config.my.users) e persistência de senhas.
{ config, inputs, ... }:
let
  inherit (config.my) users;
in
{
  flake.modules.nixos.users =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      usersWithInitialPassword = lib.filterAttrs (
        _: u: u.isNormalUser && (u.initialPassword != null || u.initialHashedPassword != null)
      ) config.users.users;
    in
    {
      programs.fish.enable = true;

      security = {
        sudo = {
          enable = true;
          wheelNeedsPassword = true;
        };
        # Administradores: KeePassXC bloqueado ao remover a YubiKey.
        keepassxc.autoLockOnYubikeyRemove.users = lib.attrNames (lib.filterAttrs (_: u: u.sudo) users);
      };

      users = {
        defaultUserShell = pkgs.fish;

        groups = {
          plugdev = { };
          dialout = { };
          docker = { };
        }
        // lib.mapAttrs (_: _: { }) users;

        users = lib.mapAttrs (name: u: {
          isNormalUser = true;
          inherit (u) uid;
          group = name;
          # Nome completo (GECOS) vindo do nix-secrets; o greeter o exibe no
          # lugar do nome de usuário (appearance.show_real_names).
          description = inputs.nix-secrets.${name}.fullName or name;
          extraGroups = [
            "users"
            "networkmanager"
            "video"
            "audio"
            "plugdev"
            "dialout"
            "docker"
          ]
          ++ lib.optional u.sudo "wheel";
          shell = pkgs.fish;
          # Definida pelo install.sh; se ficar a inicial, a sessão avisa até a
          # troca (ver detectInitialPasswords).
          initialPassword = "nixos";
        }) users;
      };

      # ── Persistência de /etc/shadow ────────────────────────────────────────
      # passwd/chage e o script de ativação "users" trocam /etc/shadow por
      # rename() atômico, o que desfaz qualquer bind mount. Por isso:
      #  1. restoreShadow copia /persist/etc/shadow → /etc/shadow ANTES do
      #     script "users" (com mutableUsers, as senhas existentes são mantidas);
      #  2. persistShadow (path unit, PathChanged) copia de volta a cada mudança.
      system.activationScripts.restoreShadow = {
        deps = [ "etc" ];
        text = ''
          mkdir -p /persist/etc
          if [ -f /persist/etc/shadow ]; then
            install -m 640 /persist/etc/shadow /etc/shadow
          fi
        '';
      };
      system.activationScripts.users.deps = [ "restoreShadow" ];

      systemd = {
        paths.persistShadow = {
          description = "Watch /etc/shadow to persist password changes";
          wantedBy = [ "multi-user.target" ];
          pathConfig = {
            PathChanged = "/etc/shadow";
            Unit = "persistShadow.service";
          };
        };

        services.persistShadow = {
          description = "Persist /etc/shadow to /persist/etc/shadow";
          # Reavalia o aviso de senha inicial a cada mudança de senha.
          wants = [ "detectInitialPasswords.service" ];
          before = [ "detectInitialPasswords.service" ];
          serviceConfig.Type = "oneshot";
          script = ''
            mkdir -p /persist/etc
            if [ -f /etc/shadow ]; then
              ${pkgs.coreutils}/bin/install -m 640 /etc/shadow /persist/etc/shadow
            fi
          '';
        };

        # Aviso de senha inicial. O Noctalia Greeter não implementa a troca de
        # senha expirada (pam_acct_mgmt: NEW_AUTHTOK_REQD), então a senha NÃO é
        # expirada com `chage -d 0`. Em vez disso, a cada boot e a cada mudança
        # em /etc/shadow, este serviço testa se a senha de cada usuário ainda é
        # a inicial e marca /run/initial-password/<usuario>; a sessão mostra um
        # aviso persistente até a troca (home/base/initial-password.nix).
        services.detectInitialPasswords = lib.mkIf (usersWithInitialPassword != { }) {
          description = "Detect users still on their initial password";
          wantedBy = [ "multi-user.target" ];
          after = [ "local-fs.target" ];
          serviceConfig.Type = "oneshot";
          script = ''
            install -d -m 0755 /run/initial-password
            ${pkgs.python3}/bin/python3 -I - ${lib.escapeShellArgs (lib.attrNames usersWithInitialPassword)} <<'PY'
            import ctypes, os, sys
            crypt = ctypes.CDLL("${pkgs.libxcrypt}/lib/libcrypt.so").crypt
            crypt.restype = ctypes.c_char_p
            hashes = {}
            with open("/etc/shadow") as f:
                for line in f:
                    parts = line.split(":")
                    hashes[parts[0]] = parts[1]
            for user in sys.argv[1:]:
                h = hashes.get(user, "")
                flag = "/run/initial-password/" + user
                initial = h[:1] == "$" and crypt(b"nixos", h.encode()) == h.encode()
                if initial:
                    open(flag, "w").close()
                elif os.path.exists(flag):
                    os.remove(flag)
            PY
          '';
        };
      };
    };
}
