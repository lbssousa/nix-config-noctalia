# Instalação

Guia para instalar `barbudus` ou `bigodon` a partir da ISO do NixOS. O
`scripts/install.sh` automatiza quase tudo; os passos manuais que restam são
o Secure Boot e o TPM2, feitos depois do primeiro boot.

## Pré-requisitos

- ISO gráfica ou mínima do NixOS (unstable) num pendrive.
- Acesso ao cofre do Bitwarden, com as chaves migradas (ver
  [Chaves no Bitwarden](#chaves-no-bitwarden)), **ou** a YubiKey (chave SSH
  residente para o GitHub e chave GPG para o git-crypt do `nix-keys`).
- Firmware em modo UEFI, com Secure Boot **desligado** e, de preferência, já
  em **Setup Mode** (chaves de fábrica apagadas) — ver [Secure Boot](#secure-boot).
- Internet no ambiente live (cabo, ou `nmtui`).

## Instalação automatizada

### Com o Bitwarden (recomendado)

```bash
# 1. No ambiente live, como o usuário comum (não root)
nix-shell -p git openssh bitwarden-cli secretspec
# Login com a YubiKey OTP como segundo fator (--method 3): a senha mestra vai
# por variável de ambiente e o código é digitado pelo toque LONGO na YubiKey
# (slot 2; o slot 1 guarda o desafio-resposta HMAC-SHA1).
read -r -s -p "Senha mestra: " BW_PASSWORD; echo; export BW_PASSWORD
read -r -p "Segure a YubiKey por ~3 s (OTP no toque longo): " BW_OTP
export BW_SESSION="$(bw login <e-mail> --passwordenv BW_PASSWORD --method 3 --code "$BW_OTP" --raw)"
unset BW_PASSWORD BW_OTP
git clone https://github.com/lbssousa/nix-config-noctalia /tmp/nix-config-noctalia
cd /tmp/nix-config-noctalia
secretspec check -P install               # confere se tudo está no cofre
bash scripts/import-ssh-yubikey.sh        # SSH do nix-secrets com a YubiKey

# 2. Instalação (SEM sudo: o script lê o Bitwarden e só então se eleva)
bash scripts/install.sh --age-keys-from-bitwarden

# 3. No fim
bw lock
```

O passo 0a do script lê, pelo perfil `install` do `secretspec.toml`:

- `AGE_KEY_SYSTEM` → `/persist/etc/sops/age/keys.txt` (passo 6b);
- `AGE_KEY_<LOGIN>` → `~/.config/sops/age/keys.txt` de cada usuário instalado
  (passo 7b, depois do `nixos-install`).

As chaves age ficam num diretório 0700 em `$XDG_RUNTIME_DIR` (RAM), apagado ao
fim do script. O `nix-keys` e o git-crypt não são necessários; a YubiKey ainda
dá o SSH para o `nix-secrets` (chave residente, `import-ssh-yubikey.sh`) e o
OTP do login no Bitwarden. Outra chave já carregada no `ssh-agent` também
serve para o `nix-secrets`.

O `~/.ssh/config` que o `import-ssh-yubikey.sh` gera reaproveita a conexão
por 10 min (`ControlMaster`): um toque na YubiKey cobre todas as buscas do
`nix-secrets` nessa janela, também as do root. As chaves de host do
`github.com` vêm fixadas no `install.sh` (o root do live não tem
`known_hosts`).

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

O script:

1. lê as chaves do Bitwarden ou desbloqueia o `nix-keys` (chaves age do sops-nix);
2. pergunta o host e o disco, e grava o disco em `modules/hosts/<host>/default.nix`;
3. particiona com o disko (`--flake .#<host>`): ESP + LUKS (`crypted`) → LVM
   (`root_vg`: swap para hibernação + btrfs com `@home @nix @persist @log
   @containers @flatpak @snapshots`); `/` é tmpfs;
4. cria `modules/users/<usuario>.nix` para usuários novos (a partir de
   `modules/users/_template.nix.in`) — o nome completo vem do `nix-secrets`;
5. cria as chaves do Secure Boot em `/persist/etc/secureboot` (sbctl);
6. copia a chave age do host para `/persist/etc/sops/age/keys.txt`;
7. copia a configuração para `/persist/etc/nixos` e roda `nixos-install`;
8. define as senhas (`/persist/etc/shadow`) e, opcionalmente, registra a
   YubiKey para `pam_u2f` (`/persist/etc/u2f-mappings`).

Modo não interativo:

```bash
sudo bash scripts/install.sh --host bigodon --disk /dev/nvme0n1 \
  --user "abutre:Laércio:sudo" --non-interactive
```

`bash scripts/inspect-installation.sh` confere o resultado antes do reboot.

## Primeiro boot

- O greeter (Noctalia Greeter) mostra o nome completo de cada usuário.
- Usuários sem senha definida no passo 8 entram com `1234`, que já está
  expirada: o greeter pede a senha atual (`1234`), a nova e a confirmação, e
  só então abre a sessão. Isso depende dos patches do greetd e do Noctalia
  Greeter no overlay (`modules/flake/packages.nix`); se a confirmação não
  bater, o login volta ao início e a senha continua expirada.
- A chave age pessoal do `abutre` já foi gravada pelo passo 7b na instalação
  pelo Bitwarden. Na instalação pelo `nix-keys`, clone-o e desbloqueie-o em
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
just switch        # NixOS + home-manager (avaliação como usuário, ativação com sudo)
just update        # atualiza o flake.lock (e faz commit/push, salvo auto_commit=false)
just upgrade       # update + switch
just diff          # pacotes que mudariam
just gc 14d        # coleta de lixo
just validate      # nixfmt + statix + deadnix + flake check
```

O `just switch` roda o `nixos-rebuild --sudo`: o flake (incluindo o input
`git+ssh` do `nix-secrets`) é avaliado pelo próprio usuário, que alcança o
GitHub pelo agente SSH do Bitwarden — nada precisa ser repassado ao root.

A chave residente da YubiKey só é usada no ambiente live (`import-ssh-yubikey.sh`).
No sistema instalado, abra o Bitwarden, ative o agente SSH e guarde no cofre
uma chave SSH registrada no GitHub com acesso ao `nix-secrets` (o agente do
Bitwarden não suporta chaves `-sk`/FIDO2) antes do primeiro `just switch`.

## Chaves no Bitwarden

O perfil `install` do `secretspec.toml` declara o que a instalação precisa. No
cofre, as chaves age são **notas seguras** (o arquivo `keys.txt` inteiro no
corpo da nota) com títulos `secretspec/nix-config-noctalia/install/<CHAVE>`.

Migração, uma vez, com o `nix-keys` desbloqueado (`nix develop` traz o
`secretspec`; o `bw` vem de `nix shell nixpkgs#bitwarden-cli`):

```bash
export BW_SESSION="$(bw unlock --raw)"
secretspec set AGE_KEY_SYSTEM -P install --from-file ../nix-keys/sops/age/keys.txt
secretspec set AGE_KEY_ABUTRE -P install --from-file ../nix-keys/sops/age/abutre/keys.txt
secretspec check -P install

# Confira se as chaves públicas batem com os recipients do .sops.yaml do nix-secrets
secretspec get AGE_KEY_SYSTEM -P install | age-keygen -y
```

Para outro usuário com segredos no home-manager, declare `AGE_KEY_<LOGIN>` no
perfil `install` e grave a chave do mesmo jeito. Mantenha o `nix-keys` como
cópia fria até a primeira instalação pelo Bitwarden dar certo.

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

**sudo bloqueado com `pam_u2f`:** sem entrada em `/persist/etc/u2f-mappings`
para o usuário, o `pam_u2f` só é usado se `security.fido2Auth.enable` estiver
ligado no host; registre a chave com `just yubikey-register`.
