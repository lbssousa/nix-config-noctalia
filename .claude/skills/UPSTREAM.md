# Skills de Nix e NixOS

Cópias, sem alteração, de skills do
[olafkfreund/nix-skills](https://github.com/olafkfreund/nix-skills) (MIT), na
revisão `f5c8e8b3b3255e323e5b84192d0b6ed2e79ef4f4` (24/11/2026). O Claude Code
as carrega como skills deste projeto.

| Skill | Para quê | Licença do conteúdo |
|---|---|---|
| `nix-language` | Escrever, explicar e depurar expressões Nix | LGPL-2.1 (manual do Nix), `COPYING` |
| `nix-workflow` | Comandos Nix, dev shells, depurar builds, configuração do Nix | MIT, `LICENSE` |
| `nixos-operations` | Rebuilds, gerações e rollback, upgrades, GC, boot e serviços | MIT (Nixpkgs), `COPYING` |
| `home-manager` | Home Manager (aqui, como módulo NixOS) | MIT, `LICENSE` |
| `nixpkgs-development` | Pacotes, overrides, overlays e helpers do Nixpkgs | MIT (Nixpkgs), `COPYING` |
| `nixos-wiki` | Consulta offline a um recorte da NixOS Wiki (`scripts/wiki.py`, só leitura) | `COPYING` |

Ficaram de fora as que não se aplicam a este repositório: `devenv-project`,
`microvm-nix`, `nix-darwin` e `nixos-coding-agents`.

As referências descrevem as revisões upstream registradas em cada
`sources.json`, não necessariamente o nixpkgs deste `flake.lock`.

Atualizar: baixar a revisão nova, comparar (`diff -r`) e conferir o que mudou
antes de substituir, porque o conteúdo vira instrução para o agente.
