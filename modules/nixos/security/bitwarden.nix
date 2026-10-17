# Bitwarden (Flatpak) como gerenciador de senhas padrão e agente SSH de todos
# os usuários (ver home/security/bitwarden.nix).
{
  flake.modules.nixos.bitwarden = {
    services.flatpak.packages = [ "com.bitwarden.desktop" ];

    # Ação polkit exigida pelo desbloqueio biométrico (digital/senha do
    # sistema): sem ela, a opção nem aparece nas configurações do app.
    environment.etc."polkit-1/actions/com.bitwarden.Bitwarden.policy".text = ''
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE policyconfig PUBLIC
       "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
       "http://www.freedesktop.org/standards/PolicyKit/1.0/policyconfig.dtd">

      <policyconfig>
          <action id="com.bitwarden.Bitwarden.unlock">
            <description>Unlock Bitwarden</description>
            <message>Authenticate to unlock Bitwarden</message>
            <defaults>
              <allow_any>no</allow_any>
              <allow_inactive>no</allow_inactive>
              <allow_active>auth_self</allow_active>
            </defaults>
          </action>
      </policyconfig>
    '';
  };
}
