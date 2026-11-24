# Desbloqueio automático do LUKS pelo TPM2 (systemd-cryptenroll).
#
# Depois da instalação e do Secure Boot ativo, rode `scripts/enroll-tpm2.sh`:
# PCRs 0+2+7 (firmware, option ROMs e estado do Secure Boot) mais o PCR 15
# exigido em zero. Se as medições mudarem, o initrd pede a senha do LUKS.
#
# PCR 15: com tpm2-measure-pcr=yes, o systemd-cryptsetup estende o PCR 15 com
# a chave do volume logo depois de abri-lo. Como o TPM só libera a chave com o
# PCR 15 ainda zerado, ela sai uma única vez, antes de qualquer volume ser
# aberto: nem um volume LUKS forjado no lugar do verdadeiro (aberto pelo initrd
# com a chave do atacante, que então tentaria pedir a chave ao TPM) nem o
# sistema já em execução conseguem obtê-la.
#
# A política (PCRs e valores) fica no token do LUKS, gravada pelo
# enroll-tpm2.sh; o crypttab não repete a lista de PCRs.
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
          "tpm2-measure-pcr=yes"
        ];
      };

      environment.systemPackages = with pkgs; [
        tpm2-tools
        tpm2-tss
      ];
    };
}
