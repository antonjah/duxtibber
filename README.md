# duxtibber

Electricity prices in your [Dux Shell](https://github.com/duxlabs-dev/dux-shell) bar. The current price sits in the bar; click it for today's and tomorrow's prices, lowest/average/highest, the cheapest slot ahead, and your last 24 h of consumption.

![screenshot](docs/screenshot.png)

Three data modes:

- **Tibber token:** your own home, prices and consumption.
- **Price area (no token):** free spot prices for SE1-SE4 or NO1-NO5.
- **Neither:** Tibber's demo data.

## Install (home-manager flakes)

Add the input and module:

```nix
# flake.nix
inputs.duxtibber = {
  url = "github:antonjah/duxtibber";
  inputs.nixpkgs.follows = "nixpkgs";
};

# in homeManagerConfiguration modules:
duxtibber.homeModules.default
```

Configure (all options except `enable` are optional):

```nix
programs.duxtibber = {
  enable = true;
  tokenFile = "~/.config/tibber/token"; # file with only your token, from developer.tibber.com
  priceArea = "SE3";                    # used when there is no token
  priceUnit = "minor";                  # "major" = SEK/kWh, "minor" = öre/kWh (øre, ct)
  showUnit = true;                      # "200 öre" instead of "200" in the bar and popup
  refreshMinutes = 15;                  # 5, 15, 30 or 60
};
```

Add the widget to your bar. The plugin does not show up until you do this too: installing it does not place it. Add the entry to the widget list of your existing bar (`leftWidgets`, `centerWidgets` or `rightWidgets`); its place in the list is its place in the bar.

```nix
programs.dank-material-shell.settings.barConfigs = [{
  # ...your existing bar settings...
  rightWidgets = [
    # ...your existing widgets...
    { id = "duxTibber"; enabled = true; }
  ];
}];
```

If your bar is not managed by Nix, add it in Dux instead: Settings > Bar widgets.

Rebuild and restart Dux, then enable the plugin once: Settings > Plugins, change the filter so disabled plugins are listed, and switch Tibber on. Or run `dms ipc call plugins enable duxTibber`.

`programs.duxtibber.enable` only installs the plugin. Turning it on is a separate switch in Dux, kept out of Nix on purpose: declaring it there would make home-manager overwrite your other plugins' settings. Until it is enabled, the bar widget stays empty.

So three things are needed: the module (installs it), the bar entry (places it) and the switch in Dux (turns it on).

After updating the plugin, restart Dux again. "Reload plugin" keeps showing the old files.

## Car (optional)

Shows your connected car's charge in the popup. Off by default.

![car tile](docs/car-tile.png)

```nix
programs.duxtibber.car = {
  enable = true;
  # name = "Enyaq";   # which car, if you have several
};
```

Rebuild and restart Dux, then do this once. The popup shows the same steps and moves on by itself.

1. Create an API client at https://data-api.tibber.com/clients/manage. Any name, tick the vehicle and home permissions, and set the redirect address to exactly `http://localhost:8765/callback` (nothing listens there). Tibber shows the client secret only once.
2. Save the secret alone in a file: `~/.config/tibber/data-api-secret`.
3. Enter the client ID in Settings > Plugins > Tibber > Car > Client ID and press Enter (or set `car.clientId = "...";` in Nix).
4. In the popup, click "Open Tibber login" and approve. The browser then says it can't connect. That is expected: copy the whole address from its address bar, go back to the popup and click "Use the address I copied".

The car tile appears. Tokens are kept in `~/.local/state/duxtibber` and refreshed automatically.