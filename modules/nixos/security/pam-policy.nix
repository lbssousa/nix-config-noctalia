# Quem pede autenticação e com o quê.
#
#   login (TTY e greetd, que inclui o login)  só a senha
#   sudo, run0, polkit-1                      digital → FIDO2 → senha
#   tela de bloqueio (noctalia-lock)          digital ou FIDO2 ou senha
#
# Digital: pam_fprintd com até 3 tentativas de 10 s cada; um timeout encerra a
# etapa e passa à seguinte. FIDO2 (security.fido2Auth): o pam_u2f só pede o
# toque se uma chave cadastrada para o usuário estiver conectada; sem ela,
# falha na hora e segue para a senha. Os dois são "sufficient": nenhum deles
# tranca a conta, a senha sempre fica no fim.
#
# A tela de bloqueio da Noctalia usa o serviço "noctalia-lock" (patch em
# modules/flake/packages.nix; sem ele seria o "login") e lê a digital por
# conta própria, pelo D-Bus, em paralelo com o campo de senha (3 tentativas).
# Por isso o pam_fprintd fica fora dessa pilha. Enter com o campo vazio pede o
# toque na YubiKey; com uma senha digitada, o pam_u2f é pulado.
{
  flake.modules.nixos.pam-policy =
    {
      config,
      lib,
      pkgs,
      ...
    }:

    let
      fido2 = config.security.fido2Auth.enable;

      fprintdSettings = {
        max-tries = 3;
        timeout = 10;
      };

      # pam_exec expose_authtok: a senha digitada chega pelo stdin. Sai com 0
      # só se ela estiver vazia.
      authtokEmpty = pkgs.writeShellScript "pam-authtok-empty" ''
        [ -z "$(${pkgs.coreutils}/bin/head -c1)" ]
      '';
    in
    {
      security.pam.services = {
        login = {
          fprintAuth = false;
          u2f.enable = false;
        };
        greetd = {
          fprintAuth = false;
          u2f.enable = false;
        };

        # fprintd antes do yubikey-notify (10850) e do pam_u2f (10900); no run0,
        # depois do pam_timestamp (400).
        sudo.rules.auth.fprintd = {
          order = lib.mkForce 10700;
          settings = fprintdSettings;
        };
        run0.rules.auth.fprintd = {
          order = lib.mkForce 500;
          settings = fprintdSettings;
        };
        "polkit-1".rules.auth.fprintd = {
          order = lib.mkForce 10700;
          settings = fprintdSettings;
        };

        noctalia-lock = {
          fprintAuth = false;
          rules.auth.u2fOnlyIfEmpty = lib.mkIf fido2 {
            # Senha digitada: pula o módulo seguinte (pam_u2f).
            control = "[success=ignore default=1]";
            modulePath = "${pkgs.linux-pam}/lib/security/pam_exec.so";
            args = [
              "quiet"
              "expose_authtok"
              "${authtokEmpty}"
            ];
            order = config.security.pam.services.noctalia-lock.rules.auth.u2f.order - 10;
          };
        };
      };

      # Enter com o campo vazio chega ao PAM (para o toque na YubiKey).
      home-manager.sharedModules = lib.optional fido2 {
        programs.noctalia.settings.lockscreen.allow_empty_password = lib.mkDefault true;
      };
    };
}
