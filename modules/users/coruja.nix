# Usuário coruja. Overrides home-manager declarativos vão em `home`;
# ajustes locais (não versionados) ficam nos arquivos *.local / local.* do
# próprio usuário — ver README, "Camadas de configuração".
{
  my.users.coruja = {
    uid = 1002;
    home = { };
  };
}
