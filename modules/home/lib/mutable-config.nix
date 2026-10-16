# Helper para programas sem "include": config gravável = base Nix ← .local.
#
#   my.mutableConfigs."starship.toml" = { format = "toml"; base = { ... }; };
#
# Em cada switch:
#   ~/.config/<arquivo>.nix-base  ← base declarada (symlink para a store)
#   ~/.config/<arquivo>           ← base mesclada em profundidade com
#                                    ~/.config/<arquivo>.local (do usuário),
#                                    gravada como arquivo comum e editável.
# Edições feitas direto no arquivo final são sobrescritas no próximo switch:
# o lugar delas é o .local (`config-diff <arquivo>` mostra o que mudou).
{
  flake.modules.homeManager.mutable-config =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.my.mutableConfigs;
      python = pkgs.python3.withPackages (ps: [ ps.tomli-w ]);

      merge = pkgs.writeScript "merge-config" ''
        #!${python}/bin/python3 -I
        import json, os, sys, tomllib, tomli_w
        fmt, base, local, out = sys.argv[1:5]
        load = (lambda f: tomllib.load(f)) if fmt == "toml" else json.load
        def deep(a, b):
            for k, v in b.items():
                a[k] = deep(a[k], v) if isinstance(v, dict) and isinstance(a.get(k), dict) else v
            return a
        with open(base, "rb") as f:
            data = load(f)
        if os.path.exists(local):
            with open(local, "rb") as f:
                data = deep(data, load(f))
        tmp = out + ".tmp"
        with open(tmp, "wb") as f:
            if fmt == "toml":
                tomli_w.dump(data, f)
            else:
                f.write(json.dumps(data, indent=2).encode())
        os.replace(tmp, out)
      '';

      generate =
        name: c:
        if c.format == "toml" then
          (pkgs.formats.toml { }).generate name c.base
        else
          (pkgs.formats.json { }).generate name c.base;
    in
    {
      options.my.mutableConfigs = lib.mkOption {
        default = { };
        description = "Arquivos de ~/.config mesclados com um <arquivo>.local do usuário.";
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              format = lib.mkOption {
                type = lib.types.enum [
                  "toml"
                  "json"
                ];
                default = "toml";
              };
              base = lib.mkOption {
                type = lib.types.attrsOf lib.types.anything;
                default = { };
              };
            };
          }
        );
      };

      config = lib.mkIf (cfg != { }) {
        xdg.configFile = lib.mapAttrs' (
          name: c: lib.nameValuePair "${name}.nix-base" { source = generate name c; }
        ) cfg;

        home.activation.mutableConfigs = lib.hm.dag.entryAfter [ "linkGeneration" ] (
          lib.concatStrings (
            lib.mapAttrsToList (
              name: c:
              let
                path = "${config.xdg.configHome}/${name}";
              in
              ''
                run ${merge} ${c.format} ${lib.escapeShellArg "${path}.nix-base"} \
                  ${lib.escapeShellArg "${path}.local"} ${lib.escapeShellArg path}
              ''
            ) cfg
          )
        );

        home.packages = [
          (pkgs.writeShellScriptBin "config-diff" ''
            f="''${XDG_CONFIG_HOME:-$HOME/.config}/$1"
            [ -n "$1" ] && [ -e "$f.nix-base" ] || {
              echo "Uso: config-diff <arquivo>  (${lib.concatStringsSep ", " (lib.attrNames cfg)})" >&2
              exit 1
            }
            ${pkgs.diffutils}/bin/diff -u "$f.nix-base" "$f"
          '')
        ];
      };
    };
}
