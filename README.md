# Disney Infinity Portal

A [CrabeLoader](https://github.com/LucasLhomme/CrabeLoader) mod that brings the physical **Disney Infinity base** back to **Disney Infinity 3.0: Gold Edition (PC)**.

You put a figure on the base and you play that character with **the figure's own level, experience and skills**, as on console. The game keeps a separate progression for each physical figure, apart from the characters you pick with the PC's virtual reader. If you turn it on, your progress can also be saved back onto the figure.

---

## Features

- **Physical bases**
  - Xbox One base (`0E6F:0229`, PDP INF-8037059). Tested.
  - Xbox 360 base (`24C6:FA00`, PDP INF-8032385). Written from the engine's driver, untested.
  - PS3 / PS4 / Wii / Wii U / PC base (`0E6F:0129`, plain HID). Written from the engine's driver, untested.
- **Figures picked up live:** place a figure on Player 1 or Player 2 to play it; lift it to go back to your previous character.
- **One progression per figure:** each figure enters the game under its own UID, with the level, experience and skills stored on it. The game applies them itself and keeps that figure's progression apart from every other character.
- **Saving to figures (optional, off by default)**
  - When the game saves a figure's progression, the mod can write it back onto the figure.
  - The write follows the console's own rule: the older of the figure's two copies is replaced, the newer one is never touched.
  - Every write is read back and checked.
  - Only the experience and skill blocks are ever written. The figure's identity and owner data are never touched.
  - A reset requested by the game is never copied to the figure.
- **LEDs:** each player slot lights up when a figure is on it, and the menu has LED tests.
- **Virtual figures:** place any character on a slot from the menu, no base needed.

## Requirements

- Disney Infinity 3.0: Gold Edition (Steam, PC).
- CrabeLoader with portal support (`Crabe.Portal` and `Crabe.Gateway`).
- CrabeMenu, for the in-game menu (`F5`).

## Installation

Copy `mod.json`, `portal.lua` and `figure_progress.lua` into:

```text
Disney Infinity 3.0 Gold Edition/mods/disneyinfinityportal/
```

From a clone of this repository, `deploy.ps1` does the same. Edit `$gameDir` first if your game is not under `D:\SteamLibrary`.

## Drivers

| Base | Driver |
|---|---|
| PS3 / PS4 / Wii / Wii U / PC | None: Windows sees it as a HID device. |
| Xbox One | **WinUSB**, installed with [Zadig](https://zadig.akeo.ie/). |
| Xbox 360 | **WinUSB**, installed with Zadig. |

Windows' own Xbox driver loads for the Xbox One base, but it does not expose the base to applications. That is why WinUSB is needed.

To install WinUSB with Zadig:

1. Plug the base in and start Zadig.
2. Select **Options > List All Devices**.
3. Pick **Disney Infinity Base** (`0E6F 0229` for Xbox One). Do not pick a controller.
4. Choose **WinUSB** and click **Replace Driver**.
5. Unplug the base and plug it back in.

To go back to the Windows driver, uninstall the device in Device Manager, tick *Delete the driver software*, then plug the base back in.

## Using it

1. Start the game with the base plugged in. The Xbox One base authenticates in about a second.
2. Place a figure on **Player 1** or **Player 2**. Its slot lights up and the character changes.
3. Lift the figure to go back to the character you had before.
4. In CrabeMenu (`F5`), the **Disney Infinity Base** category offers:
   - **Base status:** base type, the figure on each slot and its level.
   - **Save progress to figures:** off by default. Turn it on to write the game's saves onto your figures.
   - **LED tests**, **virtual figures** and **figure removal**.

Everything the mod does is logged to `loader.log` in the game folder, prefixed `[DisneyInfinityPortal]`.

## Status

| Feature | State |
|---|---|
| Xbox One base: connection, authentication, figure detection | Works in game |
| Reading a figure's progression | Works |
| One progression per figure inside the game | New; being tested |
| Saving to figures | Written, verified against a simulated figure; off by default until tested on hardware |
| Xbox 360 and HID bases | Untested (no hardware yet) |

Back up a figure you care about before turning saving on. Bug reports with your `loader.log` are welcome.

## How it works

CrabeLoader talks to the base on its own thread and decrypts each figure with its per-figure key. It then reports the figure to this mod as an event.

The mod adds the figure to the game's own figure registry, the same code path the console uses for a real reader. The game therefore treats it as a real figure. When the game saves that figure, CrabeLoader catches the write and the mod can copy it to the figure.

The details are in CrabeLoader's [portal guide](https://github.com/LucasLhomme/CrabeLoader/blob/dev/docs/guides/portal.md).

## Credits

Lucas Lhomme. Built on CrabeLoader.
