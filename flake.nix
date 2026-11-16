{
  description = "Tibber electricity prices for Dux Shell";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      forAll = f: nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (s: f nixpkgs.legacyPackages.${s});

      plugin =
        pkgs:
        pkgs.runCommand "duxtibber" { } ''
          mkdir $out
          for f in plugin.json DuxTibber.qml DuxTibberSettings.qml TibberPopout.qml PriceChart.qml StatTile.qml CarTile.qml CarSetup.qml LinkButton.qml Tibber.js; do
            cp ${self}/$f $out/$f
          done
        '';
    in
    {
      packages = forAll (pkgs: {
        default = plugin pkgs;
      });

      homeModules.default =
        { config, lib, pkgs, ... }:
        let
          cfg = config.programs.duxtibber;
          opt = type: description: lib.mkOption { type = lib.types.nullOr type; default = null; inherit description; };
        in
        {
          options.programs.duxtibber = {
            enable = lib.mkEnableOption "the Tibber price widget for Dux Shell";
            tokenFile = opt lib.types.str "Path to a file with only your Tibber token. Keep it out of the nix store (agenix, sops, or a plain file); null uses ~/.config/tibber/token.";
            homeId = opt lib.types.str "Tibber home ID; null uses the first home with a subscription.";
            priceArea = opt (lib.types.enum [ "SE1" "SE2" "SE3" "SE4" "NO1" "NO2" "NO3" "NO4" "NO5" ]) "Free spot prices for this area when no token is present.";
            priceUnit = opt (lib.types.enum [ "major" "minor" ]) "Whole currency (major) or minor unit such as öre (minor).";
            showUnit = opt lib.types.bool "Append the unit to prices in the bar and popup (default true).";
            refreshMinutes = opt (lib.types.enum [ 5 15 30 60 ]) "Minutes between price refreshes.";
            car = {
              enable = opt lib.types.bool "Show your connected car's charge in the popup (default false). The popup guides you through the one-time Tibber login.";
              name = opt lib.types.str "Name, model or ID of the car to show; null uses the first car in your account.";
              clientId = opt lib.types.str "Client ID of your Tibber Data API client (data-api.tibber.com/clients/manage, redirect address http://localhost:8765/callback).";
              clientSecretFile = opt lib.types.str "Path to a file with only the client secret; keep it out of the nix store. null uses ~/.config/tibber/data-api-secret.";
            };
          };

          config = lib.mkIf cfg.enable {
            programs.dank-material-shell.plugins.duxTibber.src = plugin pkgs;
            xdg.configFile."tibber/config.json".text = builtins.toJSON (
              lib.filterAttrs (_: v: v != null) {
                inherit (cfg) tokenFile homeId priceArea priceUnit showUnit refreshMinutes;
                showCar = cfg.car.enable;
                carName = cfg.car.name;
                carClientId = cfg.car.clientId;
                carSecretFile = cfg.car.clientSecretFile;
              }
            );
          };
        };

      checks = forAll (pkgs: {
        logic = pkgs.runCommand "duxtibber-logic" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
          cd ${self} && node --test 'tests/*.test.mjs' && touch $out
        '';

        manifest = pkgs.runCommand "duxtibber-manifest" { nativeBuildInputs = [ pkgs.jq ]; } ''
          jq -e '
            .id == "duxTibber" and .type == "widget"
            and (.component | test("^\\./")) and (.requires_dms | test("^>=\\d+\\.\\d+\\.\\d+$"))
            and ((.permissions - ["settings_read", "settings_write", "process", "network"]) | length == 0)
          ' ${self}/plugin.json && touch $out
        '';
      });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.nodejs
            pkgs.jq
            pkgs.python3
            pkgs.xvfb
            pkgs.kdePackages.qtdeclarative
          ];
        };
      });
    };
}
