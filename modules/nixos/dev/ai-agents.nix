# Agentes de IA instalados para todos os usuários.
{
  flake.modules.nixos.ai-agents =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        claude-code
        opencode
        antigravity-ide
        antigravity-cli
      ];
    };
}
