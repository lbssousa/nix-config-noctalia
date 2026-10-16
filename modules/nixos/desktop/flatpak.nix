# Flatpak disponível só para uso pontual: nenhum app é declarado aqui, e o
# padrão do projeto é usar pacotes Nix nativos.
{
  flake.modules.nixos.flatpak = {
    services.flatpak.enable = true;
  };
}
