# Perfis NetworkManager da rede de casa: SSIDs do nix-secrets (não são
# segredos) e senha via sops-nix, renderizada só em tempo de ativação.
{ inputs, ... }:
let
  inherit (inputs.nix-secrets.wifi) ssid5g ssid24g;

  profile = ssid: uuid: placeholder: ''
    [connection]
    id=${ssid}
    uuid=${uuid}
    type=wifi
    autoconnect=true

    [wifi]
    mode=infrastructure
    ssid=${ssid}

    [wifi-security]
    auth-alg=open
    key-mgmt=wpa-psk
    psk=${placeholder}

    [ipv4]
    method=auto

    [ipv6]
    addr-gen-mode=default
    method=auto
  '';
in
{
  flake.modules.nixos.wifi-home =
    { config, ... }:
    let
      psk = config.sops.placeholder.wifi_password;
      template = name: content: {
        inherit content;
        path = "/etc/NetworkManager/system-connections/${name}.nmconnection";
        mode = "0600";
        owner = "root";
        group = "root";
      };
    in
    {
      sops.secrets.wifi_password.key = "wifi/password";

      sops.templates = {
        "home-wifi-5g.nmconnection" = template "home-wifi-5g" (
          profile ssid5g "16c9c8f0-5e66-4368-8d26-95b2c6ff810d" psk
        );
        "home-wifi-2.4g.nmconnection" = template "home-wifi-2.4g" (
          profile ssid24g "cd867d94-2953-4c4b-87fd-ace0cdacc886" psk
        );
      };
    };
}
