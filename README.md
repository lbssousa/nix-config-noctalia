# nix-config-noctalia

Configuração NixOS (flake) com o compositor **Umbriel**, a shell **Noctalia** e
o **Noctalia Greeter**, inspirada no [Omarchy](https://omarchy.org): atalhos,
tema Tokyo Night, web apps, prompt e TUIs do Omarchy, com os apps gráficos de
usuário do Flathub e o resto em Nix. Sucessor do [nix-config](https://github.com/lbssousa/nix-config).

- Root efêmero (`/` em tmpfs) com [preservation](https://github.com/nix-community/preservation);
  btrfs sobre LVM sobre LUKS, swap com hibernação.
- Secure Boot (systemd-boot + lanzaboote, chaves do sbctl), boot sem
  cintilação (sem menu, Plymouth desde o logo do firmware) e desbloqueio do
  LUKS por TPM2 nos dois hosts.
- Segredos no repositório privado `nix-secrets` (sops-nix); chaves age no `nix-keys`.
- **Bitwarden** (app desktop em Flatpak e `bw` nativo) é o gerenciador de senhas padrão. Para
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
| Firefox (web apps) | o próprio Firefox; os web apps declarados voltam a ter URL e container | `firefox-webapps` (home/desktop/firefox.nix) |
| Flatpaks (permissões) | `flatpak override --user` ou o Flatseal | `services.flatpak.overrides` (nixos/desktop/flatpak.nix) |
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
- **Firefox** (Flatpak) é o navegador padrão de todos (salvo `my.browser` por usuário).
  - **Políticas:** vão na extensão `org.mozilla.firefox.systemconfig`. Instalam o Bitwarden, o Multi-Account Containers e os "<empresa> Container" (Facebook, Google, Microsoft, Twitter, Discord, Amazon e TikTok). As demais extensões vêm da sincronização com a conta Mozilla.
  - **Web apps:** são Taskbar Tabs, cada um no container da sua empresa, abertos por `webapp <id>` em *tiled fullscreen* no Umbriel: WhatsApp (Facebook), Teams (Microsoft), YouTube e Google Maps/Photos/Messages/Contacts (Google).
- **Brave** (Flatpak) é o segundo navegador.
  - **Políticas** (`/etc/brave/policies`): extensão do Bitwarden, Brave Origin (`my.brave.origin`) e as cores da Noctalia (`BrowserThemeColor`, do template `chromium-based` da comunidade).
  - **Bitwarden:** o app em Flatpak não suporta o Brave em Flatpak. O native messaging funciona por um ajuste declarado (`modules/home/desktop/brave.nix`).
  - **PWAs manuais:** o override `~/.local/share/icons:create` e o `brave-pwa-fix` corrigem `StartupWMClass`, `Exec=` e o ícone nos lançadores no Wayland (brave/brave-browser#60360).
- **Luciole**, o gerenciador de arquivos da Noctalia, é o padrão de todos:
  pastas, "Mostrar na pasta" (`org.freedesktop.FileManager1`) e o diálogo de
  abrir/salvar (portal FileChooser, com o GTK de reserva), também nos apps Qt.
  Ainda fora do nixpkgs, vem do flake do próprio projeto
  (`github:noctalia-dev/luciole`), compilado no [cache binário](#cache-binário),
  e segue as cores da Noctalia pelo template que vem no pacote.
- **Apps de usuário do Flathub** (nix-flatpak, `modules/nixos/desktop/flatpak.nix` e `apps.nix`):
  - **Apps:** Papers, mpv (decodificação por hardware), OnlyOffice, Xournal++, LocalSend, Zoom, OBS, Kdenlive, Pinta, Inkscape, FontForge e o Dropbox (de quem tem `my.dropbox.enable`), além de Flatseal, Warehouse e Bazaar para gerenciar os Flatpaks.
  - **Atualização:** os apps instalam no switch e atualizam todo dia, com os dados em `~/.var/app/<id>`.
  - **Aparência:** seguem a da Noctalia (`adw-gtk3`, `gtk.css` e ícones do usuário).
  - **Ficam em Nix:** o que não está no Flathub, os terminais, os editores (FHS, com as toolchains do host), o zathura (vimtex com SyncTeX) e o que plugins e scripts chamam pela linha de comando.
- **ArtCraft Launcher e ArtCraft** (storytold) vêm do remoto Flatpak OCI oficial do projeto (`getartcraft.com/artcraft-oci.flatpakrepo`, assinado), em `modules/nixos/desktop/artcraft.nix`. Atualizam com os demais Flatpaks.
- Do Omarchy 4.5: TCP BBR com fq e o escalonador kyber nos discos
  (`modules/nixos/core/kernel-tuning.nix`).
- Agentes de IA para todos: Claude Code, OpenCode e Antigravity CLI (Antigravity IDE no perfil de abutre).

### Atalhos principais (Super = Mod)

| Atalho | Ação | Atalho | Ação |
|---|---|---|---|
| `Super+Return` | terminal (ghostty) | `Super` (sozinho) | launcher |
| `Super+Shift+B` | Firefox | `Super+Alt+Space` | central de controle |
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
| `Super+1…9` | área de trabalho | `Super+Shift+Y/P/S` | YouTube/Photos/Maps |
| `Super+Shift+Alt+G` | WhatsApp | `Super+Ctrl+W` | papéis de parede |
| `Super+Ctrl+K` | Configurações › Segurança (digitais, YubiKey, SSH) | | |

Caps Lock vira Esc, e Shift+Caps Lock é o Caps Lock (opção XKB
`caps:escape_shifted_capslock`, no TTY, no greeter e no Umbriel).

A tabela completa está em `modules/home/desktop/umbriel.nix`.

## Ferramentas

`nix develop` traz `just`, `nixfmt`, `statix`, `deadnix`, `nvd`, `sops`, `age`,
`secretspec` e `bitwarden-cli`. O `secretspec.toml` declara os segredos de desenvolvimento/CI
(o sops-nix continua cuidando dos segredos do sistema).

O CI (`.github/workflows/validate.yml` e `update-noctalia-nix.yml`) precisa
do secret `NIX_SECRETS_SSH_KEY` (deploy key somente leitura do `nix-secrets`);
o cache é do noctalia-nix (ver [Cache binário](#cache-binário)).
`just hooks` ativa o pre-commit (nixfmt, statix, deadnix).

O sistema é reconstruído direto do clone de trabalho (`my.flakeDir`, para o qual
`/etc/nixos` aponta), inclusive com alterações não commitadas, que marcam a
geração como `-dirty`; commit e push vêm depois. Os comandos e aliases (`nrs`, `nru`, …) estão
em [INSTALLATION.md › Manutenção](INSTALLATION.md#manutenção).

## Cache binário

A família Noctalia vem do flake
[**noctalia-nix**](https://github.com/lbssousa/noctalia-nix): Noctalia, Noctalia
Greeter, Umbriel (com o portal), Luciole e o auxiliar do `noctalia-secret-prompts`.
Os patches deste repositório são commits nos branches `nix-config` dos forks:
- [lbssousa/noctalia](https://github.com/lbssousa/noctalia/tree/nix-config): PAM da tela de bloqueio, chave de segurança, polkit e página Segurança;
- [lbssousa/noctalia-greeter](https://github.com/lbssousa/noctalia-greeter/tree/nix-config): nomes completos, prompts PAM e último usuário;
- [lbssousa/umbriel](https://github.com/lbssousa/umbriel/tree/nix-config): fullscreen no tile.

O `flake.nix` daqui segue o nixpkgs do noctalia-nix (`nixpkgs.follows`), e o
overlay (`modules/flake/packages.nix`) só acrescenta o que é deste repositório:
o wrapper da Noctalia (templates e ferramentas da página Segurança), o pinentry,
o askpass e o patch do greetd. Assim as derivações são as mesmas que o CI do
noctalia-nix publica no Cachix **lbssousa-noctalia**, que todos os hosts e o
`install.sh` usam como substituter.

**Fluxo diário (CI do noctalia-nix):**
1. Os branches `nix-config` dos forks são rebaseados sobre a release mais nova
   do upstream (o `main`, no Umbriel). O estado anterior fica numa tag
   `nix-config-<base>`; um conflito vira issue no noctalia-nix e não toca no
   branch.
2. `nix flake update`, build de tudo (com os testes da Noctalia) e envio ao
   Cachix. Só se tudo passar o `flake.lock` dele é commitado.
3. Um `repository_dispatch` dispara o `update-noctalia-nix.yml` daqui. Ele
   atualiza o input, avalia os hosts, confere que nada da família Noctalia
   seria compilado localmente e commita o lock no `main`.

**Na máquina:** o `just upgrade` só baixa. Antes de compilar, ele confere
(`--dry-run`) que nenhum pacote da família Noctalia seria compilado
localmente; se algum fosse, ele para (`ALLOW_LOCAL_NOCTALIA_BUILD=1` força).

**Segredos:**
- no noctalia-nix: `CACHIX_AUTH_TOKEN` e `FORKS_TOKEN`, cadastrados a partir
  do Bitwarden com `just noctalia-nix-secrets`;
- aqui: `NIX_SECRETS_SSH_KEY`.

**Conferir** se um pacote está no cache:

```bash
nix path-info --store https://lbssousa-noctalia.cachix.org \
  "$(nix build .#noctalia --no-link --print-out-paths)"
```

## Créditos

- [Omarchy](https://github.com/basecamp/omarchy) (MIT): prompt do starship,
  atalhos e padrões dos terminais.
- [Noctalia](https://noctalia.dev), [Umbriel](https://github.com/noctalia-dev/umbriel)
  e os autores dos plugins.
- Padrão dendritic: [mightyiam/dendritic](https://github.com/mightyiam/dendritic),
  [vimjoyer/nixconf](https://github.com/vimjoyer/nixconf).
