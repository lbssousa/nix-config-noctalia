# Quem pede autenticação e com o quê.
#
#   login (TTY e greetd, que inclui o login)  só a senha
#   sudo, run0, polkit-1                      digital → FIDO2 → senha
#   tela de bloqueio                          digital ∥ FIDO2 ∥ senha
#
# Digital: pam_fprintd com até 3 tentativas de 10 s cada; um timeout encerra a
# etapa e passa à seguinte. FIDO2 (security.fido2Auth): o pam_u2f só pede o
# toque se uma chave cadastrada para o usuário estiver conectada; sem ela,
# falha na hora e segue para a senha. Os dois são "sufficient": nenhum deles
# tranca a conta, a senha sempre fica no fim.
#
# Na tela de bloqueio da Noctalia (patches em modules/flake/packages.nix) os
# três correm em paralelo, sem Enter para a digital nem para a chave:
#   - digital: a própria Noctalia fala com o fprintd pelo D-Bus (3 tentativas),
#     por isso não há pam_fprintd em nenhuma das duas pilhas abaixo;
#   - FIDO2: "noctalia-lock-u2f", só o pam_u2f, rodado em segundo plano
#     enquanto a tela está bloqueada e de novo quando surge um /dev/hidraw*;
#   - senha: "noctalia-lock" (sem o patch seria o "login").
{
  flake.modules.nixos.pam-policy =
    { config, lib, ... }:

    let
      fido2 = config.security.fido2Auth.enable;

      fprintdSettings = {
        max-tries = 3;
        timeout = 10;
      };

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
          u2f.enable = false;
        };
        # Sem pam_unix: falha na hora se nenhuma chave cadastrada estiver
        # conectada, sem pedir senha. Sem FIDO2, nem existe (cai no "other",
        # que nega) e a Noctalia só espera a próxima chave plugada.
        noctalia-lock-u2f = lib.mkIf fido2 {
          fprintAuth = false;
          unixAuth = false;
        };
      };
    };
}
