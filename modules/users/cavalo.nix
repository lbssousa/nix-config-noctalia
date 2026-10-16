# Usuário cavalo. Overrides home-manager declarativos vão em `home`;
# ajustes locais (não versionados) ficam nos arquivos *.local / local.* do
# próprio usuário — ver README, "Camadas de configuração".
{
  my.users.cavalo = {
    uid = 1004;
    home = { };
  };
}
