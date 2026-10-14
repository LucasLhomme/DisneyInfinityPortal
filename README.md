# Disney Infinity Portal Mod

Mod officiel pour **Disney Infinity 3.0: Gold Edition (PC)** réactivant le support des portails physiques USB et fournissant une émulation de portail virtuel via **CrabeLoader**.

---

## Fonctionnalités

1. **Portails Physiques Pris en Charge :**
   - **Xbox 360** (`VID: 0x24C6, PID: 0xFA00` / PDP `INF-8032385`)
   - **Xbox One** (`VID: 0x0E6F, PID: 0x0229` / PDP `INF-8037059`) — avec le **pilote Xbox d'origine de Windows** (pas Zadig/WinUSB) : Windows authentifie le socle et CrabeLoader lui parle via `Windows.Gaming.Input`.
   - **PS3 / PS4 / Wii / Wii U / PC** (`VID: 0x0E6F, PID: 0x0129`)
2. **Détection en temps réel & In-Game Spawning :**
   - Pose d'une figurine sur le Slot Joueur 1 -> chargement automatique du personnage en jeu et éclairage LED Cyan.
   - Pose d'une figurine sur le Slot Joueur 2 -> chargement automatique du personnage Joueur 2 et éclairage LED Magenta.
   - Retrait d'une figurine -> extinction de la LED correspondante.
3. **Contrôle des LED RGB :**
   - Contrôle indépendant des 3 zones (J1, J2, Pièce centrale).
   - Test des couleurs via le menu en jeu `CrabeMenu` (`F5`).
4. **Portail Virtuel Intégré :**
   - Permet également aux joueurs sans socle physique de poser des figurines virtuelles directement depuis le menu.

---

## Installation & Déploiement

Exécuter le script PowerShell :
```powershell
.\deploy.ps1
```

Le mod sera déployé dans :
`D:\SteamLibrary\steamapps\common\Disney Infinity 3.0 Gold Edition\mods\disneyinfinityportal\`


---

## Pilotes

| Portail | Pilote |
|---|---|
| PS3 / PS4 / Wii / Wii U / PC | aucun (HID Windows) |
| Xbox 360 | WinUSB via Zadig (non testé faute de matériel) |
| Xbox One | pilote Xbox de Windows (d'origine). Si Zadig y a mis WinUSB : `research\reverse\portal\switch_driver.ps1 -To Xbox` (admin) |
