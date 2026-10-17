# Instalação

Guia para instalar `barbudus` ou `bigodon` a partir da ISO do NixOS. O
`scripts/install.sh` automatiza quase tudo; os passos manuais que restam são
o Secure Boot e o TPM2, feitos depois do primeiro boot.

## Pré-requisitos

- ISO gráfica ou mínima do NixOS (unstable) num pendrive.
- A YubiKey (chave SSH residente para o GitHub e chave GPG para o git-crypt).
- Firmware em modo UEFI, com Secure Boot **desligado** e, de preferência, já
  em **Setup Mode** (chaves de fábrica apagadas) — ver [Secure Boot](#secure-boot).
- Internet no ambiente live (cabo, ou `nmtui`).

## Instalação automatizada

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

1. desbloqueia o `nix-keys` (chaves age do sops-nix);
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
- Usuários sem senha definida no passo 8 entram com `nixos` e são obrigados a
  trocá-la (uma única vez; a flag fica em `/persist`).
- Para o `abutre`: clone e desbloqueie o `nix-keys` em
  `~/Projetos/lbssousa/nix-keys` e rode `just switch` — a ativação copia a chave
  age pessoal e o sops-nix do home-manager instala o handle da chave SSH do
  GitHub em `~/.ssh/`.

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
