# nix-config-noctalia

Configuração NixOS (flake) com o compositor **Umbriel**, a shell **Noctalia** e
o **Noctalia Greeter**, inspirada no [Omarchy](https://omarchy.org): atalhos,
tema Tokyo Night, web apps, prompt e TUIs do Omarchy, com pacotes Nix nativos
no lugar de Flatpaks. Sucessor do [nix-config](https://github.com/lbssousa/nix-config).

- Root efêmero (`/` em tmpfs) com [preservation](https://github.com/nix-community/preservation);
  btrfs sobre LVM sobre LUKS, swap com hibernação.
- Secure Boot (Limine + sbctl) e desbloqueio do LUKS por TPM2 nos dois hosts.
- Segredos no repositório privado `nix-secrets` (sops-nix); chaves age no `nix-keys`.
- **Bitwarden** é o gerenciador de senhas e o agente SSH de todos os
  usuários: `SSH_AUTH_SOCK` aponta para o socket do Bitwarden desde o início
  da sessão, e as chaves SSH (ex.: a do GitHub/`nix-secrets`) ficam no cofre.
  Cada conexão é reaproveitada por 10 min (`ControlMaster`), então a
  autorização no Bitwarden é pedida uma vez por host nessa janela.
  Ligue uma vez em Configurações → "Ativar agente SSH" (e, se quiser,
  "Iniciar na bandeja" e o desbloqueio biométrico).

Instalação: [INSTALLATION.md](INSTALLATION.md).

## Estrutura (dendritic)

`flake.nix` entrega `./modules` ao [import-tree](https://github.com/denful/import-tree):
**todo arquivo `.nix` em `modules/` é um módulo [flake-parts](https://flake.parts)**,
carregado automaticamente. Arquivos e pastas com prefixo `_` são ignorados
(dados, helpers, pacotes). Cada feature publica um módulo em
`flake.modules.nixos.<nome>` ou `flake.modules.homeManager.<nome>`.

```
modules/
├── flake/      systems, my.hosts/my.users (lib.nix), overlay e pacotes, devshell/checks
├── nixos/      features NixOS (core, desktop, security, hardware, dev, input)
│   └── workstation.nix   perfil comum que compõe as features
├── home/       features home-manager (base, desktop, security, lib)
├── hosts/      barbudus/, bigodon/ (features de hardware + disco), _disko-btrfs.nix
├── users/      um arquivo por usuário (my.users.<nome>), _template.nix.in
└── packages/   pacotes próprios (_flea, _fprintd-goodix, …) e patches
```

| Host | Hardware | Features próprias |
|---|---|---|
| `barbudus` | Dell Inspiron 14 5490 | NVIDIA PRIME (MX230), leitor Goodix, thermald |
| `bigodon` | Morefine M6 (N200) | VA-API Intel |

**Adicionar um usuário:** copie `modules/users/_template.nix.in` para
`modules/users/<nome>.nix` (ou use o `install.sh`) e acrescente
`<nome>.fullName` aos outputs do `nix-secrets`. Não há lista central.

**Adicionar um host:** crie `modules/hosts/<nome>/default.nix` com
`my.hosts.<nome>.modules = [ m.workstation … ]`.

## Camadas de configuração

Tudo o que o Nix gera para um usuário é a **camada base**. Cada programa tem um
lugar para ajustes locais do próprio usuário, que o Nix nunca apaga:

| Programa | Override local (não versionado) | Mecanismo |
|---|---|---|
| Noctalia | `~/.config/noctalia/local.toml` (qualquer `*.toml`) e a GUI (`~/.local/state/noctalia/settings.toml`, vence tudo) | mescla nativa da Noctalia |
| Umbriel | `~/.config/umbriel/local.toml` (as cores vêm da paleta da Noctalia) | `[include.optional]` |
| ghostty / kitty / foot | `~/.config/ghostty/local`, `kitty/local.conf`, `foot/local.ini` | include nativo |
| fish / bash | `~/.config/fish/conf.d/*.fish`, `~/.config/fish/local.fish`, `~/.config/bash/local.sh` | `source` |
| git | `~/.config/git/local` | `include.path` |
| ssh | `~/.ssh/config.d/*.conf` (lido antes dos blocos gerados) | `Include` |
| tmux | `~/.config/tmux/local.conf` | `source-file -q` |
| neovim / nixvim | `~/.config/nvim/local.vim` / `~/.config/nvim/lua/local.lua` | `source` / `dofile` |
| starship | `~/.config/starship.toml.local` | mescla na ativação (`my.mutableConfigs`; `config-diff starship.toml`) |
| herdr | o próprio `~/.config/herdr/config.toml` (gravável) | `programs.herdr.mutableSettings` |
| apps padrão (PDF, pastas, navegador) | `~/.config/mimeapps.list` / `xdg-mime default` | defaults via `XDG_CONFIG_DIRS` |
| web apps | `~/.local/share/applications/webapp-<id>.desktop` | precede o perfil HM |
| Firefox | `about:config` | políticas com `Status = "default"` |
| agente SSH | `~/.config/environment.d/*.conf` posterior ou `IdentityAgent` em `~/.ssh/config.d/` | `SSH_AUTH_SOCK` do Bitwarden via `environment.d` |

Overrides **declarativos** por usuário ficam em `modules/users/<nome>.nix`
(`home = { … }`); os módulos base usam `lib.mkDefault`, então esse arquivo vence.
Exemplos: o dock da Noctalia é ligado para todos e desligado para o `abutre`;
o leitor de PDF é Papers para todos e Zathura para o `abutre`; o gerenciador
de arquivos é Nautilus para todos e flea para o `abutre`.

## Desktop

- **Umbriel** em layout dwindle, com o cheatsheet de atalhos embutido (`Super+K`).
- **Noctalia** com tema Tokyo Night, dock (exceto `abutre`), clipboard, capturas,
  agente polkit e plugins fixados no `flake.lock` (fonte `path`, sem git em tempo
  de execução): `screen_recorder`, `umbriel-companion`, `screen-toolkit`,
  `emoji-picker`, `calculator-plus`, `theme-switcher`, `nix-status`, `nix-search`,
  `umbriel-monitor-control`, `printers`, `claudecode`, `opencode-companion`,
  `herdr`.
- **Templates de tema** da Noctalia recolorem ghostty, kitty, foot, GTK, Qt,
  btop e Umbriel conforme a paleta ativa.
- **Noctalia Greeter** com o patch do PR
  [noctalia-greeter#131](https://github.com/noctalia-dev/noctalia-greeter/pull/131)
  (`appearance.show_real_names`): mostra o nome completo no login.
- **Senha expirada no login gráfico:** patches locais no greetd (chama
  `pam_chauthtok` quando o PAM devolve `NEW_AUTHTOK_REQD`) e no greeter
  (mostra cada prompt no campo). Como no "definir senha no próximo login"
  do GDM, toda conta nova nasce sem senha e expirada: ao escolher o usuário,
  o greeter pede direto a nova senha e a confirmação (`nullresetok` no PAM:
  senha vazia só entra enquanto expirada).
- **Firefox** é o navegador padrão (`programs.firefox`, com o pacote de idioma
  pt-BR e políticas declarativas) e tem "Adicionar aba à barra de tarefas"
  (Taskbar Tabs) habilitado. Web apps declarativos (`webapp <id>`, perfis em
  `~/.mozilla/firefox/webapp-<id>/`): WhatsApp, YouTube, Google
  Maps/Photos/Messages/Contacts, Teams, Discord, X.
- **Apps de usuário nativos:** OnlyOffice, Xournal++, Papers, LocalSend,
  Zoom, OBS, Kdenlive, Pinta, Inkscape e FontForge, como pacotes Nix
  (`modules/nixos/desktop/apps.nix`).
- Agentes de IA para todos: Claude Code, OpenCode, Antigravity (IDE e CLI).

### Atalhos principais (Super = Mod)

| Atalho | Ação | Atalho | Ação |
|---|---|---|---|
| `Super+Return` | terminal (ghostty) | `Super` (sozinho) | launcher |
| `Super+Shift+B` | Firefox | `Super+Alt+Space` | central de controle |
| `Super+Shift+F` | arquivos (Nautilus; flea para o `abutre`) | `Super+Escape` | menu de sessão |
| `Super+Shift+N` | neovim | `Super+K` | cheatsheet de atalhos |
| `Super+Alt+Return` | tmux | `Super+Ctrl+V` | histórico do clipboard |
| `Super+Ctrl+Return` | herdr | `Super+Ctrl+E` | emojis |
| `Super+Shift+/` | Bitwarden | `Super+Ctrl+Space` | papéis de parede |
| `Super+W` | fechar janela | `Super+Shift+Ctrl+Space` | temas |
| `Super+T` / `Super+F` | flutuante / tela cheia | `Print` / `Shift+Print` | captura de região / tela |
| `Super+L` | alternar layout (dwindle/scrolling) | `Alt+Print` | gravação de tela |
| `Super+1…9` | área de trabalho | `Super+Ctrl+L` | bloquear |
| `Super+Shift+Y/P/S/X` | YouTube/Photos/Maps/X | `Super+Shift+Alt+G` | WhatsApp |

A tabela completa está em `modules/home/desktop/umbriel.nix`.

## Ferramentas

`nix develop` traz `just`, `nixfmt`, `statix`, `deadnix`, `nvd`, `sops`, `age`,
`secretspec` e `bitwarden-cli`. O `secretspec.toml` declara os segredos de desenvolvimento/CI
(o sops-nix continua cuidando dos segredos do sistema).

O CI (`.github/workflows/validate.yml`) precisa do secret
`NIX_SECRETS_SSH_KEY` (deploy key somente leitura do `nix-secrets`).
`just hooks` ativa o pre-commit (nixfmt, statix, deadnix).

## Créditos

- [Omarchy](https://github.com/basecamp/omarchy) (MIT): prompt do starship,
  atalhos, padrões dos terminais e `shell/{Commons,Ui}` usados pelo flea.
- [Noctalia](https://noctalia.dev), [Umbriel](https://github.com/noctalia-dev/umbriel)
  e os autores dos plugins.
- [flea](https://github.com/thisisgm/flea), empacotado em `modules/packages/_flea`.
- Padrão dendritic: [mightyiam/dendritic](https://github.com/mightyiam/dendritic),
  [vimjoyer/nixconf](https://github.com/vimjoyer/nixconf).
