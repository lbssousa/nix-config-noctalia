# Desbloqueio automático do LUKS pelo TPM2 (systemd-cryptenroll).
#
# Depois da instalação e do Secure Boot ativo, rode `scripts/enroll-tpm2.sh`
# (PCRs 0+2+7: firmware, option ROMs e estado do Secure Boot). Se as medições
# mudarem, o initrd pede a senha do LUKS como fallback.
{
  flake.modules.nixos.tpm2 =
    { pkgs, ... }:
    {
      security.tpm2 = {
        enable = true;
        pkcs11.enable = true;
        tctiEnvironment.enable = true;
      };

      boot.initrd = {
        kernelModules = [
          "tpm_tis"
          "tpm_crb"
        ];
        # O initrd do systemd inclui o suporte a TPM2 do systemd-cryptsetup.
        systemd.tpm2.enable = true;
        # "crypted" é o nome do volume LUKS no disko.
        luks.devices.crypted.crypttabExtraOpts = [
          "tpm2-device=auto"
          "tpm2-pcrs=0+2+7"
        ];
      };

      environment.systemPackages = with pkgs; [
        tpm2-tools
        tpm2-tss
      ];
    };
}
