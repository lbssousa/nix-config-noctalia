# Brave (Flatpak com.brave.Browser, nixos/desktop/brave.nix) de cada usuário:
# o native messaging com o Bitwarden em Flatpak e, para o dono da paleta
# (my.brave.themeOwner), as cores da Noctalia.
#
# Native messaging: o Bitwarden em Flatpak só prepara os navegadores em
# Flatpak que conhece (Firefox, Chrome, Chromium, Edge), e o Brave não é um
# deles. Ele abre o socket IPC (.app.bw.socket) e a cópia do desktop_proxy no
# diretório de native messaging de cada um que existir; o proxy, chamado pelo
# navegador, usa o primeiro socket que encontrar. Então:
#  - o diretório do Chrome em Flatpak é criado (sem o Chrome), e o Bitwarden
#    passa a usá-lo;
#  - o Brave recebe acesso a esse diretório (override do Flatpak);
#  - o manifesto com.8bit.bitwarden do Brave aponta para o proxy dali. É
#    uma cópia, e não um symlink do home.file: o alvo no /nix/store não
#    existe no sandbox, o Brave não lê o manifesto e a extensão não acha o
#    app.
# O Bitwarden precisa estar rodando (e ter iniciado depois de o diretório
# existir) para a extensão falar com o app.
#
# Cores: template de usuário com o color.json do "chromium-based" da
# comunidade, gravado direto no arquivo de política que o tmpfiles do sistema
# prepara para este usuário; o post_hook faz o Brave aberto reler as
# políticas.
{ inputs, ... }:
{
  flake.modules.homeManager.brave =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      home = config.home.homeDirectory;
      sharedHosts = ".var/app/com.google.Chrome/config/google-chrome/NativeMessagingHosts";
      braveHosts = ".var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/NativeMessagingHosts";
      brave = "/var/lib/flatpak/exports/bin/com.brave.Browser";

      manifest = pkgs.writeText "com.8bit.bitwarden.json" (
        builtins.toJSON {
          name = "com.8bit.bitwarden";
          description = "Bitwarden desktop <-> browser bridge";
          path = "${home}/${sharedHosts}/.bitwarden_desktop_proxy";
          type = "stdio";
          allowed_origins = [ "chrome-extension://nngceckbapebfimnlniiiahkandclblb/" ];
        }
      );
    in
    {
      # Depois do linkGeneration, que apaga o symlink de gerações antigas.
      home.activation.bitwardenSharedNativeMessaging = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run mkdir -p ${lib.escapeShellArg "${home}/${sharedHosts}"} ${lib.escapeShellArg "${home}/${braveHosts}"}
        run rm -f ${lib.escapeShellArg "${home}/${braveHosts}/com.8bit.bitwarden.json"}
        run install -m 0644 ${manifest} ${lib.escapeShellArg "${home}/${braveHosts}/com.8bit.bitwarden.json"}
      '';

      programs.noctalia.settings.theme.templates.user.brave =
        lib.mkIf (osConfig.my.brave.themeOwner == config.home.username)
          {
            input_path = "${inputs.noctalia-templates-community}/chromium-based/color.json";
            output_path = "/etc/brave/policies/managed/noctalia-color.json";
            post_hook = "timeout --kill-after=1s 5s ${brave} --refresh-platform-policy --no-startup-window";
          };
    };
}
