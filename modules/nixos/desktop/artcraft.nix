# ArtCraft Launcher e ArtCraft (storytold, Apache-2.0), pelo remoto Flatpak
# OCI oficial do projeto: não estão no Flathub, mas os runtimes vêm de lá.
#
# O .flatpakrepo traz a chave "ArtCraft Linux Release Signing Key" (primária
# 2B76741B414AAD6CD33E631213A005C0B9D7C3ED), que o flatpak importa no
# remote-add e usa para conferir as assinaturas das imagens. Atualizam com os
# demais Flatpaks (desktop/flatpak.nix). O launcher instala e atualiza os
# outros apps da família Craft pelo mesmo remoto.
{
  flake.modules.nixos.artcraft =
    { lib, ... }:
    {
      services.flatpak = {
        # Acrescenta ao flathub padrão do nix-flatpak, em vez de substituí-lo.
        remotes = lib.mkOptionDefault [
          {
            name = "artcraft-oci";
            location = "https://getartcraft.com/artcraft-oci.flatpakrepo";
          }
        ];
        packages = [
          {
            appId = "ai.storyteller.artcraft-launcher";
            origin = "artcraft-oci";
          }
          {
            appId = "ai.artcraft.app";
            origin = "artcraft-oci";
          }
        ];
      };
    };
}
