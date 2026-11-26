# Extensões do Zed instaladas por padrão. O editor é pacote do sistema
# (desktop/apps.nix), por isso package = null.
#
# O settings.json continua do Zed (mutableUserSettings, o padrão): a cada
# ativação, o home-manager mescla auto_install_extensions no arquivo do usuário,
# e o Zed instala o que faltar ao abrir. A mescla regrava o arquivo como JSON,
# sem os comentários.
#
# IDs do registro (github.com/zed-industries/extensions):
#  - latex: LaTeX com o texlab;
#  - gregorio: Gregorio GABC/NABC (canto gregoriano), com o gregorio-lsp.
{
  flake.modules.homeManager.zed = {
    programs.zed-editor = {
      enable = true;
      package = null;
      extensions = [
        "latex"
        "gregorio"
      ];
    };
  };
}
