# Testes NixOS (VMs) dos patches do overlay. Ficam fora de `checks` para o
# `nix flake check` do CI continuar só avaliando; rode com `just test-greetd`
# (precisa de KVM).
#
# greetd-expired-password: login com senha expirada (`chage -d 0`). Um greeter
# de teste fala o IPC do greetd (u32 de tamanho + JSON) e roda cenários, um
# usuário cada: responde os prompts secretos em ordem (senha atual no login,
# senha atual de novo no pam_chauthtok, nova senha e confirmação). Os de erro
# (senha atual errada, confirmação diferente) vêm antes e não podem abrir a
# sessão nem mexer no shadow (pam_unix "required", ver secret-service.nix); o
# último troca a senha e abre a sessão. Sem o patch do greetd, o primeiro
# post_auth_message_response já volta "pam_acct_mgmt: NEW_AUTHTOK_REQD".
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
            ("bob", ["1234", "errada", "${newPassword}", "${newPassword}"]),
            ("carol", ["1234", "1234", "${newPassword}", "Outra-Senha!"]),
            ("alice", ["1234", "1234", "${newPassword}", "${newPassword}"]),
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

      # Confere a senha de um usuário contra o /etc/shadow (crypt da libxcrypt).
      checkPassword = pkgs.writers.writePython3Bin "check-password" { flakeIgnore = [ "E501" ]; } ''
        import ctypes
        import sys

        crypt = ctypes.CDLL("${pkgs.libxcrypt}/lib/libcrypt.so").crypt
        crypt.restype = ctypes.c_char_p
        user, password = sys.argv[1], sys.argv[2].encode()
        with open("/etc/shadow") as f:
            hashes = {p[0]: p[1] for p in (line.split(":") for line in f)}
        h = hashes[user].encode()
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

            users.users = lib.genAttrs [ "alice" "bob" "carol" ] (_: {
              isNormalUser = true;
              initialPassword = "1234";
            });

            # Mesma pilha PAM do sistema: oo7 e pam_unix "required" na troca de
            # senha (modules/nixos/desktop/secret-service.nix).
            imports = [ config.flake.modules.nixos.secret-service ];

            services.greetd = {
              enable = true;
              package = patched.greetd;
              settings.default_session.command = "${testGreeter}";
            };
          };

        testScript = ''
          machine.wait_for_unit("multi-user.target")

          with subtest("senha inicial expirada"):
              for user in ["alice", "bob", "carol"]:
                  machine.succeed(f"chage -d 0 {user}")
              machine.succeed("touch /tmp/greeter.go")
              machine.wait_for_file("/tmp/greeter.done")
              transcript = machine.succeed("cat /tmp/greeter.log")
              print(transcript)

          with subtest("troca feita na conversa do greetd"):
              assert "RESULT alice success" in transcript, transcript
              lastchg = machine.succeed("awk -F: '$1 == \"alice\" { print $3 }' /etc/shadow").strip()
              assert lastchg not in ("", "0"), f"sp_lstchg ainda {lastchg!r}"

          with subtest("a nova senha vale e a inicial não"):
              machine.succeed("check-password alice '${newPassword}'")
              machine.fail("check-password alice 1234")

          with subtest("respostas recusadas não trocam a senha"):
              for user in ["bob", "carol"]:
                  assert f"RESULT {user} error" in transcript, transcript
                  machine.succeed(f"check-password {user} 1234")
                  machine.succeed(f"test \"$(awk -F: '$1 == \"{user}\" {{ print $3 }}' /etc/shadow)\" = 0")
        '';
      };
    };
}
