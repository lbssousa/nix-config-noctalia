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

      security.sudo = {
        enable = true;
        wheelNeedsPassword = true;
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
          # Só vale na criação da conta: sem senha e expirada, como o "definir
          # senha no próximo login" do GDM; a senha é escolhida no primeiro
          # login (install.sh passo 8, detectInitialPasswords e
          # security/first-login.nix).
          initialHashedPassword = "";
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

        # Conta ainda sem senha. A cada boot e a cada mudança em /etc/shadow,
        # este serviço procura usuários com a senha vazia; se houver, expira-a
        # (`chage -d 0`, só se ainda não estiver expirada, pois o chage
        # reescreve o shadow e reativa este serviço) e marca
        # /run/initial-password/<usuario>. Senha vazia só entra expirada
        # (nullresetok, security/first-login.nix); no login, o greetd
        # corrigido (overlay em modules/flake/packages.nix) chama
        # pam_chauthtok e o greeter pede só a nova senha e a confirmação. A
        # marca alimenta o aviso dentro da sessão
        # (home/base/initial-password.nix), que fica como reserva.
        services.detectInitialPasswords = lib.mkIf (usersWithInitialPassword != { }) {
          description = "Expire passwords of users who haven't set one yet";
          wantedBy = [ "multi-user.target" ];
          after = [ "local-fs.target" ];
          serviceConfig.Type = "oneshot";
          script = ''
            install -d -m 0755 /run/initial-password
            ${pkgs.python3}/bin/python3 -I - ${lib.escapeShellArgs (lib.attrNames usersWithInitialPassword)} <<'PY'
            import os, subprocess, sys
            entries = {}
            with open("/etc/shadow") as f:
                for line in f:
                    parts = line.split(":")
                    entries[parts[0]] = parts
            for user in sys.argv[1:]:
                if user not in entries:
                    continue
                h, lastchg = entries[user][1], entries[user][2]
                flag = "/run/initial-password/" + user
                if h == "":
                    if lastchg != "0":
                        subprocess.run(["${pkgs.shadow}/bin/chage", "-d", "0", user], check=True)
                    open(flag, "w").close()
                elif os.path.exists(flag):
                    os.remove(flag)
            PY
          '';
        };
      };
    };
}
