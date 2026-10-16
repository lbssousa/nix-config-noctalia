# Usuário coelho. Overrides home-manager declarativos vão em `home`;
# ajustes locais (não versionados) ficam nos arquivos *.local / local.* do
# próprio usuário — ver README, "Camadas de configuração".
{
  my.users.coelho = {
    uid = 1007;
    home = { };
  };
}
