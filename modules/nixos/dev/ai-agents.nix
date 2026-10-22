# Agentes de IA instalados para todos os usuários.
{
  flake.modules.nixos.ai-agents =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        claude-code
        opencode
        antigravity-cli
        # secret-tool: o plugin Headroom da Noctalia lê a sessão do
        # Antigravity no chaveiro (home/desktop/noctalia.nix).
        libsecret
      ];
    };
}
