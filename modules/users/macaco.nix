# Usuário macaco. Overrides home-manager declarativos vão em `home`;
# ajustes locais (não versionados) ficam nos arquivos *.local / local.* do
# próprio usuário — ver README, "Camadas de configuração".
{
  my.users.macaco = {
    uid = 1005;
    home = { };
  };
}
