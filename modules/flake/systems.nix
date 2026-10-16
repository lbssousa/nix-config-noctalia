# Base do flake: sistemas suportados e a opção flake.modules.<classe>.<nome>,
# onde cada feature publica seus módulos NixOS/home-manager.
{ inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.modules ];

  systems = [ "x86_64-linux" ];
}
