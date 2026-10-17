# Testes NixOS (VMs) dos patches do overlay. Ficam fora de `checks` para o
# `nix flake check` do CI continuar só avaliando; rode com `just test-greetd`
# (precisa de KVM).
#
# greetd-expired-password: login com senha expirada (`chage -d 0`). Um greeter
# de teste fala o IPC do greetd (u32 de tamanho + JSON) e responde os prompts
# secretos em ordem: senha atual no login, senha atual de novo no
# pam_chauthtok, nova senha e confirmação. Sem o patch do greetd, o primeiro
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
        ANSWERS = ["1234", "1234", "${newPassword}", "${newPassword}"]

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


        reply = request({"type": "create_session", "username": "alice"})
        answers = list(ANSWERS)
        while reply["type"] == "auth_message":
            if reply["auth_message_type"] in ("secret", "visible"):
                reply = request({"type": "post_auth_message_response",
                                 "response": answers.pop(0)})
            else:
                reply = request({"type": "post_auth_message_response"})

        if reply["type"] == "success":
            reply = request({"type": "start_session", "cmd": ["true"],
                             "env": []})
        log.write("RESULT " + reply["type"] + "\n")
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

        nodes.machine = {
          environment.systemPackages = [ checkPassword ];

          users.users.alice = {
            isNormalUser = true;
            initialPassword = "1234";
          };

          services.greetd = {
            enable = true;
            package = patched.greetd;
            settings.default_session.command = "${testGreeter}";
          };
        };

        testScript = ''
          machine.wait_for_unit("multi-user.target")

          with subtest("senha inicial expirada"):
              machine.succeed("chage -d 0 alice")
              machine.succeed("touch /tmp/greeter.go")
              machine.wait_for_file("/tmp/greeter.done")
              transcript = machine.succeed("cat /tmp/greeter.log")
              print(transcript)

          with subtest("troca feita na conversa do greetd"):
              assert "RESULT success" in transcript, transcript
              assert transcript.count('"auth_message_type": "secret"') == 4, transcript
              lastchg = machine.succeed("awk -F: '$1 == \"alice\" { print $3 }' /etc/shadow").strip()
              assert lastchg not in ("", "0"), f"sp_lstchg ainda {lastchg!r}"

          with subtest("a nova senha vale e a inicial não"):
              machine.succeed("check-password alice '${newPassword}'")
              machine.fail("check-password alice 1234")
        '';
      };
    };
}
