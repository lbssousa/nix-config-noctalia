{
  flake.modules.nixos.fonts =
    { pkgs, ... }:
    {
      fonts = {
        enableDefaultPackages = true;
        packages = with pkgs; [
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-color-emoji
          liberation_ttf
          adwaita-fonts
          nerd-fonts.jetbrains-mono
          nerd-fonts.caskaydia-mono
          nerd-fonts.fira-code
          nerd-fonts.hack
          nerd-fonts.meslo-lg
        ];
        fontconfig.defaultFonts = {
          serif = [ "Noto Serif" ];
          sansSerif = [
            "Adwaita Sans"
            "Noto Sans"
          ];
          monospace = [ "JetBrainsMono Nerd Font" ];
          emoji = [ "Noto Color Emoji" ];
        };
      };
    };
}
