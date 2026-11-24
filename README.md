# nix-config-noctalia

Configuração NixOS (flake) com o compositor **Umbriel**, a shell **Noctalia** e
o **Noctalia Greeter**, inspirada no [Omarchy](https://omarchy.org): atalhos,
tema Tokyo Night, web apps, prompt e TUIs do Omarchy, com pacotes Nix nativos
no lugar de Flatpaks. Sucessor do [nix-config](https://github.com/lbssousa/nix-config).

- Root efêmero (`/` em tmpfs) com [preservation](https://github.com/nix-community/preservation);
  btrfs sobre LVM sobre LUKS, swap com hibernação.
- Secure Boot (systemd-boot + lanzaboote, chaves do sbctl), boot sem
  cintilação (sem menu, Plymouth desde o logo do firmware) e desbloqueio do
  LUKS por TPM2 nos dois hosts.
- Segredos no repositório privado `nix-secrets` (sops-nix); chaves age no `nix-keys`.
- **Bitwarden** (app desktop e `bw`) é o gerenciador de senhas padrão. Para
  quem tem `my.bitwarden.enable` (por ora, o `abutre`), o agente SSH do app
  fica no `SSH_AUTH_SOCK` da sessão (ex.: a chave do GitHub/`nix-secrets`), o
  app sobe na bandeja com a sessão e as preferências dele são declaradas no
  Nix; desbloqueio pelo polkit (digital). Não há `ssh-agent` do sistema.

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
└── packages/   pacotes próprios (_fprintd-goodix, …) e patches
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
| Chrome (web apps) | os declarados são PWAs forçadas (não removíveis); outras se instalam no próprio Chrome | `WebAppInstallForceList` (nixos/desktop/google-chrome.nix) |
| agente SSH | `~/.config/environment.d/*.conf` posterior ou `IdentityAgent` em `~/.ssh/config.d/` | `SSH_AUTH_SOCK` do Bitwarden (`home/security/bitwarden.nix`) |

Overrides **declarativos** por usuário ficam em `modules/users/<nome>.nix`
(`home = { … }`); os módulos base usam `lib.mkDefault`, então esse arquivo vence.
Exemplos: o leitor de PDF é Papers para todos e Zathura para o `abutre`.

## Desktop

- **Umbriel** em layout dwindle, com o cheatsheet de atalhos embutido (`Super+K`).
- **Noctalia** com tema Tokyo Night, dock, clipboard, capturas,
  agente polkit e plugins fixados no
  `flake.lock` (fonte `path`, sem git em tempo de execução): `screen_recorder`, `timer`, `umbriel-companion`, `screen-toolkit`,
  `emoji-picker`, `calculator-plus`, `theme-switcher`, `nix-status`, `nix-search`,
  `umbriel-monitor-control`, `printers`, `headroom` (limites do Claude Code, do
  Codex e do Antigravity), `opencode-companion` e `herdr` (os três de IA
  juntos num grupo de cápsula na barra).
- **Plugin próprio** da Noctalia, em repositório separado e fixado no `flake.lock`:
  [`secret-prompts`](https://github.com/lbssousa/noctalia-secret-prompts) (pinentry do GnuPG e `SSH_ASKPASS` num painel da shell, com
  os clientes `noctalia-pinentry`/`noctalia-askpass`).
- **Configurações > Segurança** (patch da Noctalia): digitais, login com a chave
  FIDO2/U2F (pam_u2f), a chave OpenPGP do cartão e as chaves SSH residentes da
  YubiKey, com atalho na central de controle e em Mod+Ctrl+K.
- **Templates de tema** da Noctalia recolorem ghostty, kitty, foot, GTK, Qt,
  btop e Umbriel conforme a paleta ativa. Os aplicativos de terminal (alacritty,
  foot, ghostty, kitty e wezterm) usam sempre a variante escura.
- **Noctalia Greeter** com o patch do PR
  [noctalia-greeter#131](https://github.com/noctalia-dev/noctalia-greeter/pull/131)
  (`appearance.show_real_names`): mostra o nome completo no login.
- **Senha expirada no login gráfico:** patches locais no greetd (chama
  `pam_chauthtok` quando o PAM devolve `NEW_AUTHTOK_REQD`) e no greeter
  (mostra cada prompt no campo). Como no "definir senha no próximo login"
  do GDM, toda conta nova nasce sem senha e expirada: ao escolher o usuário,
  o greeter pede direto a nova senha e a confirmação (`nullresetok` no PAM:
  senha vazia só entra enquanto expirada).
- **Google Chrome** é o navegador padrão, com a extensão do Bitwarden
  (native messaging declarativo com o app; as demais extensões vêm da
  sincronização com a conta Google), as cores da Noctalia (política
  `BrowserThemeColor`, do template `chromium-based` da comunidade) e web apps
  instalados como PWAs pela política `WebAppInstallForceList` (`webapp <id>`):
  WhatsApp, Teams, YouTube, Google Maps/Photos/Messages/Contacts, Discord e X.
- **Luciole**, o gerenciador de arquivos da Noctalia, é o padrão de todos:
  pastas, "Mostrar na pasta" (`org.freedesktop.FileManager1`) e o diálogo de
  abrir/salvar (portal FileChooser, com o GTK de reserva), também nos apps Qt.
  Ainda fora do nixpkgs, vem do flake do próprio projeto
  (`github:noctalia-dev/luciole`), compilado no [cache binário](#cache-binário),
  e segue as cores da Noctalia pelo template que vem no pacote.
- **Apps de usuário nativos:** OnlyOffice, Xournal++, Papers, LocalSend,
  Zoom, OBS, Kdenlive, Pinta, Inkscape e FontForge, como pacotes Nix
  (`modules/nixos/desktop/apps.nix`); o mpv decodifica vídeo por hardware.
- Do Omarchy 4.5: TCP BBR com fq e o escalonador kyber nos discos
  (`modules/nixos/core/kernel-tuning.nix`).
- Agentes de IA para todos: Claude Code, OpenCode e Antigravity CLI (Antigravity IDE no perfil de abutre).

### Atalhos principais (Super = Mod)

| Atalho | Ação | Atalho | Ação |
|---|---|---|---|
| `Super+Return` | terminal (ghostty) | `Super` (sozinho) | launcher |
| `Super+Shift+B` | Chrome | `Super+Alt+Space` | central de controle |
| `Super+Shift+F` | arquivos (Luciole) | `Super+Escape` | menu de sessão |
| `Super+Shift+N` | neovim | `Super+K` | cheatsheet de atalhos |
| `Super+Alt+Return` | tmux | `Super+Ctrl+V` | histórico do clipboard |
| `Super+Ctrl+Return` | herdr | `Super+Ctrl+E` | emojis |
| `Super+Shift+/` | Bitwarden | `Super+Ctrl+Space` | papéis de parede |
| `Super+W` / `Super+Q` | fechar janela | `Super+Shift+Ctrl+Space` / `Super+Ctrl+T` | temas |
| `Super+T` / `Super+F` | flutuante / tela cheia | `Print` / `Shift+Print` | captura de região / tela |
| `Super+L` | bloquear | `Alt+Print` | gravação de tela |
| `Super+Ctrl+L` / `+Alt` | próximo / anterior layout (dwindle → scrolling → stacking) | `Super+Shift+T` | btop |
| `Super+J` | alternar o split (dwindle) | `Super+Shift+Q` | calculadora |
| `Super+M` / `Super+Alt+M` | minimizar / restaurar (janela flutuante) | `Super+Ctrl+N` | rede |
| `Super+S` | scratchpad | `Super+'` | console Quake (shell que desce do topo) |
| `Super+,` | agir na última notificação | `Super+Ctrl+Alt+,` | não perturbe |
| `Super+Shift+Ctrl+setas` | janela para outro monitor | `Alt+Space` | ditado (Superwhisper) |
| `Super+1…9` | área de trabalho | `Super+Shift+Y/P/S/X` | YouTube/Photos/Maps/X |
| `Super+Shift+Alt+G` | WhatsApp | `Super+Ctrl+W` | papéis de parede |
| `Super+Ctrl+K` | Configurações › Segurança (digitais, YubiKey, SSH) | | |

Caps Lock vira Esc, e Shift+Caps Lock é o Caps Lock (opção XKB
`caps:escape_shifted_capslock`, no TTY, no greeter e no Umbriel).

A tabela completa está em `modules/home/desktop/umbriel.nix`.

## Ferramentas

`nix develop` traz `just`, `nixfmt`, `statix`, `deadnix`, `nvd`, `sops`, `age`,
`secretspec` e `bitwarden-cli`. O `secretspec.toml` declara os segredos de desenvolvimento/CI
(o sops-nix continua cuidando dos segredos do sistema).

O CI (`.github/workflows/validate.yml`) precisa do secret
`NIX_SECRETS_SSH_KEY` (deploy key somente leitura do `nix-secrets`) e, para o
job `cache`, do `CACHIX_AUTH_TOKEN` (ver [Cache binário](#cache-binário)).
`just hooks` ativa o pre-commit (nixfmt, statix, deadnix).

O sistema é reconstruído direto do clone de trabalho (`my.flakeDir`, para o qual
`/etc/nixos` aponta), inclusive com alterações não commitadas, que marcam a
geração como `-dirty`; commit e push vêm depois. Os comandos e aliases (`nrs`, `nru`, …) estão
em [INSTALLATION.md › Manutenção](INSTALLATION.md#manutenção).

## Cache binário

O overlay (`modules/flake/packages.nix`) aplica patches locais na Noctalia, no
Noctalia Greeter, no Umbriel e nos plugins da comunidade, e empacota o
auxiliar do `noctalia-secret-prompts` e o Luciole (que ainda não está no
nixpkgs). Nada disso está no cache.nixos.org, e
sem um cache próprio cada host compila tudo de novo a cada atualização. Esses
pacotes vão para o Cachix **lbssousa-noctalia**, que todos os hosts usam como
substituter (`modules/nixos/core/nix.nix`) e que o `install.sh` também usa na
instalação.

O que entra no cache é o pacote `.#noctalia-cache`, que agrega a lista
`noctaliaCache` em `modules/flake/packages.nix`: `noctalia`,
`noctalia-greeter`, `pinentry-noctalia`, `noctalia-askpass`,
`noctalia-secret-prompts`, `noctalia-plugins-community`, `umbriel` e
`luciole`. Para
incluir outro pacote da família, acrescente o nome dele nessa lista. O
`cachix push` só envia o que ainda não está no cache.nixos.org.

**Configuração (uma vez):**

1. Em [app.cachix.org](https://app.cachix.org) › lbssousa-noctalia ›
   Settings › Auth Tokens, crie um token com permissão de escrita.
2. Guarde-o no Bitwarden pelo secretspec (perfil `default`; com `BW_SESSION`
   de `bw unlock --raw`):
   `secretspec set CACHIX_AUTH_TOKEN --provider bw:// --profile default`.
3. Crie o secret do GitHub com o mesmo token:
   `gh secret set CACHIX_AUTH_TOKEN -R lbssousa/nix-config-noctalia`.

**Envio:**

- **CI:** o job `cache` do `validate.yml` roda depois do `flake-check` em
  todo push no `main` (`.nix`, `flake.lock` ou patches) e também sob demanda
  (Actions › Validate Nix Files › Run workflow). Ele compila
  `.#noctalia-cache` e envia tudo o que compilou.
- **Local:** `just cache-push` compila e envia. O token vem de
  `CACHIX_AUTH_TOKEN` no ambiente ou, se a variável não existir, do
  secretspec no Bitwarden (`bw://`, com `BW_SESSION`; outro provider em
  `SECRETSPEC_PROVIDER`). Com o token no ambiente
  (`CACHIX_AUTH_TOKEN=… just upgrade`, ou `secretspec run -- just upgrade`),
  o `just upgrade` envia sozinho depois do build; se o envio falhar, o
  upgrade continua.

**Conferir** se um pacote está no cache:

```bash
nix path-info --store https://lbssousa-noctalia.cachix.org \
  "$(nix build .#noctalia --no-link --print-out-paths)"
nix config show substituters   # inclui https://lbssousa-noctalia.cachix.org
```

## Créditos

- [Omarchy](https://github.com/basecamp/omarchy) (MIT): prompt do starship,
  atalhos e padrões dos terminais.
- [Noctalia](https://noctalia.dev), [Umbriel](https://github.com/noctalia-dev/umbriel)
  e os autores dos plugins.
- Padrão dendritic: [mightyiam/dendritic](https://github.com/mightyiam/dendritic),
  [vimjoyer/nixconf](https://github.com/vimjoyer/nixconf).
