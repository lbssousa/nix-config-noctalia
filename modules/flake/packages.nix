# Pacotes próprios (modules/packages/_*/package.nix), expostos como
# packages.<system>.<nome> e pelo overlay aplicado a todos os hosts.
{ config, lib, ... }:
let
  overlay =
    final: prev:
    let
      call = path: final.callPackage path { };
    in
    {
      run0-sudo = call ../packages/_run0-sudo/package.nix;
      libfprint-goodix = call ../packages/_libfprint-goodix/package.nix;
      fprintd-goodix = call ../packages/_fprintd-goodix/package.nix;
      yubikey-gpg-import = call ../packages/_yubikey-gpg-import/package.nix;
      strata = call ../packages/_strata/package.nix;

      # Quick Unlock do KeePassXC pelo polkit (digital, FIDO2 ou senha, conforme
      # a pilha PAM "polkit-1"): backport do PR keepassxreboot/keepassxc#8983
      # (só no develop, que virará a 2.8) para a 2.7.x do nixpkgs. Os arquivos
      # novos do PR (backend Polkit, ação org.keepassxc.KeePassXC.unlockDatabase)
      # entram como estão; a integração segue a da 2.7, que identifica o banco
      # pelo caminho do arquivo (quickUnlockUuid) em vez do UUID público.
      # Remover quando o nixpkgs empacotar a 2.8.
      keepassxc = prev.keepassxc.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ../packages/patches/keepassxc-polkit-quick-unlock.patch ];
        buildInputs = (old.buildInputs or [ ]) ++ [ final.keyutils ];
      });

      # Senha expirada (pam_acct_mgmt: NEW_AUTHTOK_REQD) no login gráfico.
      # O greetd 0.10.3 só falhava; o patch chama pam_chauthtok na mesma
      # conversa, e os prompts (senha atual, nova, confirmação) chegam ao
      # greeter como auth_message. Patch local, sem PR upstream.
      greetd = prev.greetd.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ../packages/patches/greetd-change-expired-authtok.patch ];
      });

      # Noctalia Greeter, três patches (nesta ordem):
      #  - nome completo na tela de login: PR aberto
      #    https://github.com/noctalia-dev/noctalia-greeter/pull/131
      #    ([appearance] show_real_names); remover quando chegar ao nixpkgs;
      #  - prompts PAM seguintes (troca de senha expirada) no placeholder do
      #    campo, sem apagar o aviso do PAM no status; patch local;
      #  - último usuário que fez login em [user] last do sync.toml (ao lado
      #    de [session] last), pré-selecionado no boot seguinte; --user e
      #    [user].default continuam valendo mais. Patch local, sem PR upstream.
      # Tela de bloqueio da Noctalia no serviço PAM "noctalia-lock" em vez do
      # "login" (que fica só com a senha) e digital com 3 tentativas no total
      # (eram 4). Ver security/pam-policy.nix. Patch local, sem PR upstream.
      # Pinentry do GnuPG e ssh-askpass desenhados pela shell, no estilo do painel
      # do polkit: os clientes noctalia-pinentry e noctalia-askpass falam Assuan
      # com a Noctalia ([shell] pinentry / ssh_askpass). Patch local, gerado do
      # branch feat/secret-prompts de ~/Projetos/lbssousa/noctalia; sem PR upstream.
      # Destaque no painel do polkit enquanto o PAM espera a digital ou o toque
      # na YubiKey: ícone grande (impressão digital ou chave) com título e
      # descrição traduzidos, no lugar da mensagem crua do pam_fprintd/pam_u2f.
      # Aplicado sobre o anterior; patch local, sem PR upstream.
      # Toque na YubiKey desbloqueia a tela sem Enter, em paralelo com a digital
      # e a senha: o helper PAM da Noctalia roda o serviço "noctalia-lock-u2f"
      # em segundo plano ([lockscreen] security_key). Patch local, sem PR upstream.
      # Na tela de bloqueio, um método por vez: digital (até 3 leituras ou 30 s),
      # depois FIDO2 (sem chave cadastrada ou com o toque expirado, segue), depois
      # senha. Nas duas primeiras etapas o campo de senha dá lugar a um destaque
      # como o do polkit e a um botão "Usar senha"; plugar a chave com o campo
      # vazio volta à FIDO2, e a sequência recomeça a cada resume. Aplicado sobre
      # o anterior; patch local, sem PR upstream.
      #
      # O compositor Umbriel rejeita pedidos de subscribe do IPC com erro se houver
      # eventos desconhecidos, desconectando imediatamente o cliente. A Noctalia
      # pedia "outputs" (que não existe no Umbriel), impedindo a inscrição nos
      # eventos de "windows" e quebrando a ocultação inteligente da dock.
      # Os templates dos aplicativos de terminal (emuladores e starship) são
      # remapeados de `.default` para `.dark`: assim eles usam sempre a variante
      # escura da paleta ativa, mesmo com [theme].mode = "auto". Os demais
      # templates (GTK, Qt, Umbriel) continuam seguindo o modo global.
      #
      # Reempacotar os assets (em vez de usar overrideAttrs/postInstall) evita
      # recompilar a Noctalia: basta copiar a saída já construída, ajustar os
      # templates e apontar NOCTALIA_ASSETS_DIR para a cópia.
      noctalia =
        let
          base = prev.noctalia.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [
              ../packages/patches/noctalia-lock-pam-service.patch
              ../packages/patches/noctalia-secret-prompts.patch
              ../packages/patches/noctalia-polkit-auth-cues.patch
              ../packages/patches/noctalia-lock-security-key.patch
              ../packages/patches/noctalia-lock-auth-sequence.patch
              ../packages/patches/noctalia-umbriel-subscribe-without-outputs.patch
            ];
          });
        in
        final.runCommand "noctalia-${base.version}"
          {
            nativeBuildInputs = [ final.makeWrapper ];
            meta = base.meta // {
              mainProgram = "noctalia";
            };
            passthru = base.passthru or { };
          }
          ''
            mkdir -p $out
            cp -a ${base}/share $out/share
            chmod -R u+w $out/share

            for template in \
              alacritty/alacritty.toml \
              foot/foot \
              ghostty/ghostty \
              kitty/kitty.conf \
              starship/starship.toml \
              wezterm/wezterm.toml
            do
              substituteInPlace "$out/share/noctalia/assets/templates/$template" \
                --replace-fail ".default." ".dark."
            done

            mkdir -p $out/bin
            for program in noctalia noctalia-pinentry noctalia-askpass; do
              makeWrapper ${base}/bin/$program $out/bin/$program \
                --set-default NOCTALIA_ASSETS_DIR "$out/share/noctalia/assets"
            done
          '';

      # pinentry-program do gpg-agent; fora da sessão gráfica cai no pinentry-curses.
      pinentry-noctalia =
        final.runCommand "pinentry-noctalia"
          {
            nativeBuildInputs = [ final.makeWrapper ];
            meta.mainProgram = "pinentry-noctalia";
          }
          ''
            makeWrapper ${final.noctalia}/bin/noctalia-pinentry $out/bin/pinentry-noctalia \
              --set-default NOCTALIA_PINENTRY_FALLBACK ${final.pinentry-curses}/bin/pinentry-curses
          '';

      # SSH_ASKPASS (ssh, ssh-add e git); sem a shell, falha com status 1.
      noctalia-askpass = final.runCommand "noctalia-askpass" { meta.mainProgram = "noctalia-askpass"; } ''
        mkdir -p $out/bin
        ln -s ${final.noctalia}/bin/noctalia-askpass $out/bin/noctalia-askpass
      '';

      noctalia-greeter = prev.noctalia-greeter.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ../packages/patches/noctalia-greeter-show-real-names.patch
          ../packages/patches/noctalia-greeter-pam-prompts.patch
          ../packages/patches/noctalia-greeter-remember-last-user.patch
        ];
      });
    };
in
{
  flake.overlays.default = overlay;

  flake.modules.nixos.overlay = {
    nixpkgs.overlays = [ config.flake.overlays.default ];
    nixpkgs.config.allowUnfree = true;
  };

  perSystem =
    { pkgs, system, ... }:
    let
      pkgs' = import pkgs.path {
        inherit system;
        overlays = [ overlay ];
        config.allowUnfree = true;
      };
    in
    {
      packages = lib.genAttrs [
        "run0-sudo"
        "libfprint-goodix"
        "fprintd-goodix"
        "yubikey-gpg-import"
        "strata"
        "keepassxc"
        "greetd"
        "noctalia"
        "noctalia-greeter"
        "pinentry-noctalia"
        "noctalia-askpass"
      ] (n: pkgs'.${n});
    };
}
