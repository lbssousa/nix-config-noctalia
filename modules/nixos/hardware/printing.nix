# Impressora Epson L4160 em fila CUPS driverless (IPP Everywhere), declarada
# para sobreviver ao root efêmero. Sem o epson-printer-utility.
{
  flake.modules.nixos.printing =
    { pkgs, ... }:
    {
      services.printing.enable = true;

      services.avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
      };

      hardware.printers = {
        ensurePrinters = [
          {
            name = "L4160_driverless";
            location = "Wi-Fi";
            description = "L4160 (driverless)";
            deviceUri = "ipp://EPSONE0321F.local/ipp/print";
            model = "everywhere";
            # Uma falha de filtro descarta só o trabalho, sem desabilitar a fila.
            ppdOptions."printer-error-policy" = "abort-job";
          }
        ];
        ensureDefaultPrinter = "L4160_driverless";
      };

      environment.systemPackages = [ pkgs.system-config-printer ];
    };
}
