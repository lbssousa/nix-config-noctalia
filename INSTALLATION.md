# Instalação

Guia para instalar `barbudus` ou `bigodon` a partir da ISO do NixOS. O
`scripts/install.sh` automatiza quase tudo; os passos manuais que restam são
o Secure Boot e o TPM2, feitos depois do primeiro boot.

## Pré-requisitos

- ISO gráfica ou mínima do NixOS (unstable) num pendrive.
- As chaves age no Bitwarden, migradas antes (ver
  [Chaves no cofre](#chaves-no-cofre)), **ou** a YubiKey (chave SSH residente
  para o GitHub e chave GPG para o git-crypt do `nix-keys`).
- Firmware em modo UEFI, com Secure Boot **desligado** e, de preferência, já
  em **Setup Mode** (chaves de fábrica apagadas) — ver [Secure Boot](#secure-boot).
- Internet no ambiente live (cabo, ou `nmtui`).

## Instalação automatizada

### Com o cofre: Bitwarden (recomendado)

Como o usuário comum (**sem** sudo):

```bash
nix-shell -p git --run "git clone https://github.com/lbssousa/nix-config-noctalia /tmp/nix-config-noctalia"
bash /tmp/nix-config-noctalia/scripts/install-from-vault.sh
```

O `install-from-vault.sh` faz o resto:

1. traz `git`, `openssh`, `gum`, `bitwarden-cli` e `secretspec` via
   `nix shell`, do `nixpkgs` travado no `flake.lock`;
2. destrava o Bitwarden: e-mail, senha mestra e o código OTP da YubiKey
   (toque **longo**, slot 2; o slot 1 guarda o desafio-resposta HMAC-SHA1).
   Outro segundo fator: `BW_2FA_METHOD=0` (aplicativo autenticador);
3. confere se a `AGE_KEY_SYSTEM` está no cofre;
4. importa as chaves SSH residentes da YubiKey para o `nix-secrets`
   (`import-ssh-yubikey.sh`; pule com `--no-yubikey-ssh` se outra chave do
   `ssh-agent` já alcança o GitHub);
5. roda `install.sh --age-keys-from-vault` (que se eleva sozinho);
6. tranca o cofre ao sair, mesmo em caso de erro.

Sem perguntas: `--email` (ou `BW_EMAIL`). As demais opções do `install.sh`
(`--host`, `--disk`, `--user`, ...) são repassadas. O antigo
`install-from-bitwarden.sh` continua funcionando (é o `install-from-vault.sh`).

Das chaves do perfil `install`, `AGE_KEY_SYSTEM` vai para
`/persist/etc/sops/age/keys.txt` e cada `AGE_KEY_<LOGIN>` para
`~/.config/sops/age/keys.txt` do usuário, depois do `nixos-install`. Até lá
elas ficam num diretório 0700 em `$XDG_RUNTIME_DIR` (RAM), apagado ao fim. O
`~/.ssh/config` gerado pelo `import-ssh-yubikey.sh` reaproveita a conexão por
10 min (`ControlMaster`): um toque na YubiKey cobre todas as buscas do
`nix-secrets`, também as do root.

### Com a YubiKey e o nix-keys

```bash
# 1. No ambiente live: SSH com a YubiKey (extrai os handles residentes e
#    escreve ~/.ssh/config) e GPG do cartão (para o git-crypt)
nix-shell -p git git-crypt openssh gnupg
git clone https://github.com/lbssousa/nix-config-noctalia /tmp/nix-config-noctalia
bash /tmp/nix-config-noctalia/scripts/import-ssh-yubikey.sh
bash /tmp/nix-config-noctalia/scripts/import-gpg-yubikey.sh

# 2. nix-keys ao lado do repositório (o install.sh o encontra sozinho)
git clone git@github.com:lbssousa/nix-keys.git /tmp/nix-keys
git -C /tmp/nix-keys crypt unlock

# 3. Instalação (interativa)
sudo bash /tmp/nix-config-noctalia/scripts/install.sh
```

O script faz **todas as perguntas antes de qualquer ação**, num formulário
com o `gum` (como o instalador do Omarchy): host, disco, senha do LUKS,
usuários novos, chave age do sistema (se não veio do Bitwarden nem do
`nix-keys`) e, opcionalmente, a senha do root (guardada só como hash). Em
seguida mostra um resumo e pede uma única confirmação; nada toca o disco
antes disso. Em qualquer pergunta, Esc recomeça o formulário e Ctrl+C cancela.

Depois da confirmação, o script:

1. lê as chaves do Bitwarden ou desbloqueia o `nix-keys` (chaves age do
   sops-nix) — isso acontece antes do formulário;
2. grava o disco em `modules/hosts/<host>/default.nix`;
3. particiona com o disko (`--flake .#<host>`): ESP + LUKS (`crypted`) → LVM
   (`root_vg`: swap para hibernação + btrfs com `@home @nix @persist @log
   @containers @snapshots`); `/` é tmpfs;
4. cria `modules/users/<usuario>.nix` para usuários novos (a partir de
   `modules/users/_template.nix.in`) — o nome completo vem do `nix-secrets`;
5. cria as chaves do Secure Boot em `/persist/etc/secureboot` (sbctl);
6. copia a chave age do host para `/persist/etc/sops/age/keys.txt`;
7. copia a configuração para `/persist/etc/nixos` e roda `nixos-install`;
8. deixa todos os usuários sem senha e expirados, aplica a senha do root
   escolhida no formulário, grava `/persist/etc/shadow` e registra a
   YubiKey para `pam_u2f` (`/persist/etc/u2f-mappings`), se estiver conectada.

Modo não interativo (sem `gum`; sem `--luks-password-file`, o disko pede a
senha do LUKS no terminal):

```bash
sudo bash scripts/install.sh --host bigodon --disk /dev/nvme0n1 \
  --user "abutre:Laércio:sudo" --luks-password-file /run/luks.txt --non-interactive
```

`bash scripts/inspect-installation.sh` confere o resultado antes do reboot.

## Primeiro boot

- O greeter (Noctalia Greeter) mostra o nome completo de cada usuário.
- Todos os usuários começam sem senha, como no "definir senha no próximo
  login" do GDM: ao escolher o usuário, o greeter mostra "Primeiro acesso" e
  pede direto a nova senha e a confirmação, e só então abre a sessão. Isso
  depende dos patches do greetd e do Noctalia Greeter no overlay
  (`modules/flake/packages.nix`); se a confirmação não bater, o login volta ao
  início e a conta continua sem senha. Senha vazia só é aceita enquanto a
  conta está expirada (`modules/nixos/security/first-login.nix`).
- A chave age pessoal do `abutre` já foi gravada pelo passo 7b na instalação
  pelo cofre. Na instalação pelo `nix-keys`, clone-o e desbloqueie-o em
  `~/Projetos/lbssousa/nix-keys` e rode `just switch`: a ativação copia a
  chave.

## Secure Boot

Os dois hosts usam o Secure Boot nativo do Limine com chaves próprias (sbctl).
Não há shim/MOK: as chaves do projeto substituem as de fábrica no firmware.

1. No firmware, apague as chaves (Setup Mode) e mantenha o Secure Boot desligado.
2. Inicie o sistema e rode:
   ```bash
   sudo bash /etc/nixos/scripts/setup-secureboot.sh   # verifica, assina e cadastra as chaves
   just boot                                           # regrava os binários assinados
   ```
3. Ligue o Secure Boot no firmware e reinicie; confira com `sudo sbctl status`.

## Desbloqueio do LUKS por TPM2

Depois do Secure Boot ativo (o PCR 7 mede o estado dele):

```bash
sudo bash /etc/nixos/scripts/enroll-tpm2.sh             # PCRs 0+2+7 em /dev/disk/by-partlabel/luks
sudo bash /etc/nixos/scripts/enroll-tpm2.sh --wipe      # refaz o cadastro (ex.: após atualizar o firmware)
```

Se as medições mudarem, o initrd (systemd) pede a senha do LUKS como antes.

## Leitor de digital (barbudus)

```bash
fprintd-enroll
fprintd-verify
```

## Manutenção

```bash
just switch        # NixOS + home-manager (avaliação como usuário, ativação com run0)
just update        # atualiza o flake.lock (e faz commit/push, salvo auto_commit=false)
just upgrade       # update + switch
just diff          # pacotes que mudariam
just gc 14d        # coleta de lixo
just validate      # nixfmt + statix + deadnix + flake check
```

O `just switch` roda o `nixos-rebuild --elevate run0`: o flake (incluindo o input
`git+ssh` do `nix-secrets`) é avaliado pelo próprio usuário, que alcança o
GitHub pelo agente SSH do Bitwarden (`SSH_AUTH_SOCK`) — nada precisa ser repassado ao root.

A chave residente da YubiKey só é usada no ambiente live (`import-ssh-yubikey.sh`).
No sistema instalado, guarde no Bitwarden (item do tipo **Chave SSH**) uma
chave registrada no GitHub com acesso ao `nix-secrets` antes do primeiro
`just switch`: o agente SSH do app (ligado em `my.bitwarden.enable`, ver
`modules/home/security/bitwarden.nix`) a oferece ao `ssh`, e cada uso é
autorizado no próprio Bitwarden até o cofre travar.

## Chaves no cofre

O perfil `install` do `secretspec.toml` declara o que a instalação precisa. O
nome do projeto ali (`lbssousa-nixos`) não é o de um repositório: é o mesmo
em todas as configurações NixOS (nix-config-noctalia, nix-config-omarchy, ...),
que leem as mesmas entradas:

**notas seguras** no Bitwarden (o arquivo `keys.txt` inteiro no corpo da
nota) com títulos `secretspec/lbssousa-nixos/install/<CHAVE>`.

Entradas gravadas antes com o nome antigo (`secretspec/nix-config-noctalia/…`)
não são mais lidas: grave-as de novo com o `store-age-keys` (abaixo) e apague
as notas antigas no Bitwarden.

Migração, uma vez, com o `nix-keys` desbloqueado ao lado deste repositório:

```bash
nix develop -c just store-age-keys   # ou: --nix-keys-dir <dir> --email <e-mail>
```

O script destrava o Bitwarden como o `install-from-vault.sh`,
grava cada `AGE_KEY_*` declarada a partir do `nix-keys` (`sops/age/keys.txt`
para o sistema, `sops/age/<login>/keys.txt` para os usuários), lê cada uma de
volta e mostra a chave pública — confira com os recipients do `.sops.yaml`
do `nix-secrets`. Rodar de novo atualiza as entradas.

Para outro usuário com segredos no home-manager, declare `AGE_KEY_<LOGIN>` no
perfil `install` e rode a migração de novo. Mantenha o `nix-keys` como
cópia fria até a primeira instalação pelo cofre dar certo.

## Problemas comuns

**Sistema não inicia depois de mexer no firmware/TPM2:** digite a senha do LUKS
(fallback) e rode `enroll-tpm2.sh --wipe`.

**Recuperação pelo pendrive:**

```bash
sudo cryptsetup open /dev/disk/by-partlabel/luks crypted
sudo vgchange -ay root_vg
sudo mount -t tmpfs none /mnt
sudo mkdir -p /mnt/{boot,nix,persist,home}
sudo mount -o subvol=@nix /dev/root_vg/root /mnt/nix
sudo mount -o subvol=@persist /dev/root_vg/root /mnt/persist
sudo mount -o subvol=@home /dev/root_vg/root /mnt/home
sudo mount /dev/disk/by-partlabel/ESP /mnt/boot
sudo nixos-enter --root /mnt
```

**Depurar a instalação no ambiente live:** o `live-opencode.sh` abre o
opencode na raiz do clone (a versão do `nixos-unstable`, que vem pronta do
cache). Com `--upstream`, usa a última release do projeto, compilada do
código-fonte (demora e consome RAM do store em tmpfs).

```bash
bash /tmp/nix-config-noctalia/scripts/live-opencode.sh
bash /tmp/nix-config-noctalia/scripts/live-opencode.sh --upstream
```

**Digital, YubiKey ou senha?** O login (TTY e tela de login) aceita só a
senha. `sudo`, `run0` e os pedidos do polkit tentam, nesta ordem, a digital
(até 3 tentativas de 10 s), a YubiKey (só se uma chave cadastrada estiver
conectada) e a senha. Na tela de bloqueio, a digital fica ativa o tempo todo;
Enter com o campo vazio pede o toque na YubiKey. Detalhes em
`modules/nixos/security/pam-policy.nix`; cadastre a YubiKey com
`just yubikey-register` (`/persist/etc/u2f-mappings`).
