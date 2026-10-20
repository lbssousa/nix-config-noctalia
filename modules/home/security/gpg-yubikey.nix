# YubiKey para o usuário: ferramentas, e (opcional) GPG com a chave OpenPGP
# do cartão para assinar commits. O gpg-agent NÃO faz papel de agente SSH.
{
  flake.modules.homeManager.yubikey =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.my.yubikeyGpg.enable = lib.mkEnableOption "GPG com a chave OpenPGP da YubiKey";

      config = lib.mkMerge [
        {
          home.packages = with pkgs; [
            yubikey-manager
            yubioath-flutter
            pam_u2f
          ];
        }

        (lib.mkIf config.my.yubikeyGpg.enable {
          home.packages = with pkgs; [
            yubico-piv-tool
            yubikey-gpg-import
          ];

          programs.gpg = {
            enable = true;
            settings = {
              keyid-format = "0xlong";
              with-fingerprint = true;
            };
            # O pcscd do sistema já fala com a YubiKey; o scdaemon usa PC/SC
            # em vez de disputar o USB via CCID.
            scdaemonSettings.disable-ccid = true;
          };

          services.gpg-agent = {
            enable = true;
            enableScDaemon = true;
            enableSshSupport = false;
            enableFishIntegration = true;
            defaultCacheTtl = 1800;
            maxCacheTtl = 7200;
            # O mesmo do sistema (nixos/security/secret-prompts.nix).
            pinentry.package = pkgs.pinentry-noctalia;
          };
        })
      ];
    };
}
