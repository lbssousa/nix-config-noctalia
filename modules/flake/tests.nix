# Testes NixOS (VMs) dos patches do overlay. Ficam fora de `checks` para o
# `nix flake check` do CI continuar só avaliando; rode com `just test-greetd`
# (precisa de KVM).
#
# greetd-expired-password: primeiro login de uma conta sem senha e expirada
# (`chage -d 0`), como o "definir senha no próximo login" do GDM. Um greeter
# de teste fala o IPC do greetd (u32 de tamanho + JSON) e roda cenários, um
# usuário cada, respondendo os prompts secretos em ordem. Numa conta sem senha
# e expirada o pam_unix nem pede a senha: a conversa começa na nova senha e
# na confirmação (sem "senha atual"). Os de erro vêm antes e
# não podem abrir a sessão nem mexer no shadow:
#   - bob: senha vazia não expirada → o nullresetok recusa (first-login.nix);
#   - carol: confirmação diferente → pam_unix "required" (secret-service.nix).
# O último (alice) define a senha e abre a sessão. Sem o patch do greetd, o
# primeiro post_auth_message_response já volta
# "pam_acct_mgmt: NEW_AUTHTOK_REQD".
{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      patched = pkgs.extend config.flake.overlays.default;
      newPassword = "S3nha-Nova!";

      testGreeter = pkgs.writers.writePython3 "greetd-test-greeter" { flakeIgnore = [ "E501" ]; } ''
        import json
        import os
        import socket
        import struct
        import time

        LOG = "/tmp/greeter.log"
        DONE = "/tmp/greeter.done"
        GO = "/tmp/greeter.go"
        SCENARIOS = [
            ("bob", [""]),
            ("carol", ["${newPassword}", "Outra-Senha!"]),
            ("alice", ["${newPassword}", "${newPassword}"]),
        ]

        # greetd relança o greeter quando a sessão de teste termina.
        if os.path.exists(DONE):
            while True:
                time.sleep(3600)
        while not os.path.exists(GO):
            time.sleep(0.2)

        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(os.environ["GREETD_SOCK"])
        log = open(LOG, "w")


        def recv_exact(n):
            buf = b""
            while len(buf) < n:
                chunk = sock.recv(n - len(buf))
                if not chunk:
                    raise EOFError("greetd closed the connection")
                buf += chunk
            return buf


        def request(msg):
            data = json.dumps(msg).encode()
            sock.sendall(struct.pack("=I", len(data)) + data)
            (size,) = struct.unpack("=I", recv_exact(4))
            reply = json.loads(recv_exact(size))
            log.write(json.dumps(reply) + "\n")
            log.flush()
            return reply


        for user, answers in SCENARIOS:
            log.write(f"SCENARIO {user}\n")
            reply = request({"type": "create_session", "username": user})
            while reply["type"] == "auth_message":
                if reply["auth_message_type"] in ("secret", "visible"):
                    response = answers.pop(0) if answers else ""
                    reply = request({"type": "post_auth_message_response",
                                     "response": response})
                else:
                    reply = request({"type": "post_auth_message_response"})
            if reply["type"] == "success":
                reply = request({"type": "start_session", "cmd": ["true"],
                                 "env": []})
                log.write(f"RESULT {user} {reply['type']}\n")
                break
            desc = reply.get("description", "")
            log.write(f"RESULT {user} error {desc}\n")
            request({"type": "cancel_session"})
        log.close()
        open(DONE, "w").close()
      '';

      # Confere a senha de um usuário contra o /etc/shadow (crypt da libxcrypt);
      # hash vazio confere com a senha vazia.
      checkPassword = pkgs.writers.writePython3Bin "check-password" { flakeIgnore = [ "E501" ]; } ''
        import ctypes
        import sys

        crypt = ctypes.CDLL("${pkgs.libxcrypt}/lib/libcrypt.so").crypt
        crypt.restype = ctypes.c_char_p
        user, password = sys.argv[1], sys.argv[2].encode()
        with open("/etc/shadow") as f:
            hashes = {p[0]: p[1] for p in (line.split(":") for line in f)}
        h = hashes[user].encode()
        if not h:
            sys.exit(0 if not password else 1)
        sys.exit(0 if crypt(password, h) == h else 1)
      '';
    in
    {
      legacyPackages.tests.greetd-expired-password = pkgs.testers.runNixOSTest {
        name = "greetd-expired-password";

        nodes.machine =
          { lib, ... }:
          {
            environment.systemPackages = [ checkPassword ];

            # Sem senha, como as contas do sistema (users.nix).
            users.users = lib.genAttrs [ "alice" "bob" "carol" ] (_: {
              isNormalUser = true;
              initialHashedPassword = "";
            });

            # Mesma pilha PAM do sistema: nullresetok (first-login.nix), oo7 e
            # pam_unix "required" na troca de senha (secret-service.nix).
            imports = with config.flake.modules.nixos; [
              first-login
              secret-service
            ];

            services.greetd = {
              enable = true;
              package = patched.greetd;
              settings.default_session.command = "${testGreeter}";
            };
          };

        testScript = ''
          machine.wait_for_unit("multi-user.target")

          with subtest("contas sem senha; só alice e carol expiradas"):
              for user in ["alice", "carol"]:
                  machine.succeed(f"chage -d 0 {user}")
              machine.succeed("touch /tmp/greeter.go")
              machine.wait_for_file("/tmp/greeter.done")
              transcript = machine.succeed("cat /tmp/greeter.log")
              print(transcript)

          with subtest("senha definida direto, sem pedir a senha atual"):
              assert "RESULT alice success" in transcript, transcript
              alice = transcript.split("SCENARIO alice")[1]
              assert "Current password" not in alice and '"Password: "' not in alice, alice
              assert alice.count('"auth_message_type": "secret"') == 2, alice
              lastchg = machine.succeed("awk -F: '$1 == \"alice\" { print $3 }' /etc/shadow").strip()
              assert lastchg not in ("", "0"), f"sp_lstchg ainda {lastchg!r}"
              machine.succeed("check-password alice '${newPassword}'")
              machine.fail("check-password alice '''")

          with subtest("senha vazia não expirada não entra"):
              assert "RESULT bob error pam_authenticate: AUTH_ERR" in transcript, transcript
              machine.succeed("check-password bob '''")

          with subtest("confirmação diferente não define a senha"):
              assert "RESULT carol error pam_chauthtok" in transcript, transcript
              machine.succeed("check-password carol '''")
              machine.succeed("test \"$(awk -F: '$1 == \"carol\" { print $3 }' /etc/shadow)\" = 0")
        '';
      };
    };
}
