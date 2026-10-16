# STATUS — Mod portail Disney Infinity

**Mis à jour :** 14 octobre 2026, 16 h
**Demande initiale :** « un mod qui puisse faire fonctionner tous les portails ».
**Détails techniques :** `AUDIT.md` (même dossier).

> **« Une fiche par figurine » validée en jeu (17:46).** Joy arrive au niveau 9 avec sa propre fiche, le niveau gagné est vu par le mod (`the game saved level 10 …`). CrabeLoader : PR #33 ouverte vers `dev` ; mod poussé sur `main`. L'écriture sur la figurine reste **désactivée** et jamais testée. À voir : la forme bleue au retrait (le mod remet aussitôt l'avatar du lecteur virtuel), l'écriture réelle sur Joy (accord explicite de Lucas requis).

---

## 1. En une page

| Portail                                         | Code                          | Compilé | Testé sur matériel       | État                                                                                                              |
| ----------------------------------------------- | ----------------------------- | -------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| **Xbox One** `0E6F:0229` (INF-8037059)  | GIP + auth v1 + canal`0x21` | oui      | **oui, en jeu**      | **Fonctionne** : authentification au lancement, Joy détectée, événement reçu par le mod. WinUSB requis. |
| PS3 / PS4 / Wii / Wii U / PC (HID`0E6F:0129`) | transport HID + protocole     | oui      | non (pas de portail)       | Écrit d'après le moteur, sans pilote à installer.                                                               |
| Xbox 360`24C6:FA00`                           | WinUSB, enveloppe`0B 15`    | oui      | non (pas de portail)       | Écrit d'après le moteur. WinUSB (Zadig) requis.                                                                  |
| Portail virtuel (menu F5)                       | primitives Lua                | oui      | oui (session précédente) | Fonctionne.                                                                                                        |

| Fonction                                                      | État                                                                                                |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Lecture de l'identité (SKU, UID)                             | **Validée en jeu** (Joy, SKU 1000216, sur Joueur 1).                                          |
| LED                                                           | Commandes envoyées et acquittées par le socle ; allumage non confirmé visuellement.               |
| Lecture de la progression de la figurine                      | **Validée hors jeu** (niveau 9, 102 XP, 3 compétences).                                      |
| Figurine dans le moteur sous son propre UID (fiche séparée) | Écrite et déployée,**jamais exécutée en jeu** (§3). Remplace l'approche « fusion ».    |
| Écriture de la progression sur la figurine                   | Écrite, testée hors ligne (18/18),**désactivée**, jamais exécutée sur la vraie figurine. |

---

## 2. Ce qui a été fait le 14/10

### 2.1 Xbox One : de « bloqué » à « fonctionne en jeu »

Les deux erreurs qui bloquaient tout depuis le matin :

1. **Mauvais canal.** Les rapports Disney passent par le message GIP **`0x21`** (non système, 32 octets), pas `0x1F`. Source : pilote Xbox One du socle dans le code du moteur, `Octane/Code/Engine/LowLevel/Platform/Gateway/InfinityBaseDriver/GenericGip.h` (`Request::ID = Report::ID = 0x21`). Le `0x21` figure aussi dans le descripteur IDENTIFY.
2. **Fin d'authentification.** Le firmware PDP n'envoie jamais de CLIENT_FINISH : il acquitte la requête `0x08` au niveau GIP, et l'hôte doit alors envoyer le contrôle COMPLETE (`06 20 seq 02 | 01 00`), comme Windows (voir le projet XboxHeadsetBridge, casque PDP). Redemander le CLIENT_FINISH bloque le socle jusqu'au débranchement.

L'authentification est **obligatoire** (sans elle, `0x21` est ignoré ; vérifié sur socle fraîchement rebranché).

**Impasse documentée :** le pilote Xbox de Windows (`dc1-controller`) charge, mais n'expose le socle ni à `Windows.Gaming.Input.Custom` ni à GameInput 3.5 (qui n'existe d'ailleurs qu'en 64 bits). WinUSB est obligatoire. `research\reverse\portal\switch_driver.ps1 -To WinUsb|Xbox` bascule (admin) ; le paquet Zadig est sauvegardé dans `research\reverse\portal\driver_backup\`.

**Test en jeu (14:01) :** `Portal: Xbox One base authenticated` → `base awake (firmware 12.7)` → `figure sku 1000216 on antenna 2` → `[DisneyInfinityPortal] Figurine posee sur Joueur 1 : Joy`.

### 2.2 Progression des figurines

- **Lecture (C++)** : après le bloc d'identité, lecture des copies S1B0/S2B0 (expérience) et S1B1/S2B1 (compétences), déchiffrement + CRC, choix de la copie courante comme le moteur. Validé sur Joy : niveau 9, 102 XP (dans le niveau), compétences JOY_HEALTH1, JOY_PARRY, JOY_SPECIAL_UNLOCKED. Format complet : `AUDIT.md` §3.7.
- **Écriture (C++)** : `DisneyBaseProtocol::WriteProgress` écrit chaque paire modifiée dans sa copie la plus ancienne (séquence + 1, CRC, AES, commande `0xA3`), puis **relit et compare** (le moteur, lui, ne relit pas). Garde-fou dur : seuls les secteurs 1-2, blocs 0-1 peuvent être écrits. Test hors ligne `test_portal_write.exe` contre une figurine simulée avec les vrais blocs de Joy : 18/18 (chiffrement identique aux octets réels, copies courantes et identité intactes).
- **Lua** : `portalFigurePlaced(slot, sku, uid, progress)`, `Crabe.Portal.writeFigureProgress(slot, progress)`.
- **Mod** : `figure_progress.lua` (application au PC + écriture périodique), `figure_skills.lua` (table bit → compétence pour 169 arbres, générée depuis le gamedb par `tools/gen_figure_skills.lua`).
- **Sauvegarde brute de Joy** (lecture seule, avant toute écriture) : `research\reverse\portal\figure_04685c82173f80_20261014_141128.json`.

### 2.3 Refonte C++ (branche locale `feature/portal-support`, rien de commité dans CrabeLoader)

`{include,src}/infrastructure/portal/` : `portal_types`, `portal_protocol` (sans E/S, testable), `portal_crypto` (CNG : clé par figurine, AES, CRC moteur, `DecryptDataBlock`, `SealDataBlock`), `portal_transports.cpp` (HID, Xbox 360, découverte), `portal_transport_gip.cpp` (Xbox One), `usb_device`, `portal_worker` (thread dédié, reconnexion à chaud), `portal_service`. Natives : `_portalGetStatus`, `_portalSetLed`, `_portalPollEvent` (+ progression), `_portalWriteProgress`, `_portalEmulatePlace/Remove`. Cibles de test : `portal_probe` (worker réel en console), `test_portal_write` (hors ligne).

Le mod lui-même a été commité par Lucas (`DisneyInfinityPortal`, commit `ae6042c init: project`, 15:31) ; `figure_progress.lua` a été modifié depuis (écriture désactivée par défaut).

---

## 3. Une fiche par figurine (prêt pour le test en jeu)

**Constat.** Sur PC, il n'y a qu'**une progression par personnage**, partagée par le lecteur virtuel et le portail. La version déployée « fusionne » donc figurine et PC (niveau le plus haut, compétences réunies). Effets indésirables : la progression du lecteur virtuel finit sur la figurine, deux figurines du même personnage convergent, un respec PC est annulé à la pose suivante, et aucun niveau ne peut baisser (le jeu n'a que des fonctions de montée de niveau).

**Ce que fait vraiment le moteur.** La sauvegarde range la progression **par UID de figurine** (`IGP::AvatarInProfile(TagUID)`, `IGP.cpp:73`). Le lecteur virtuel PC pose de fausses puces dont l'UID est l'identifiant du personnage (`g_Gateway.AddTag(id, id, 0,0,0,0,0,0)`, `VirtualReader.cpp:1166`). Une vraie figurine posée sous son vrai UID aurait donc **sa propre fiche**, comme sur console.

**Ce qui est fait (16:05, non testé en jeu) :**

1. Reverse de l'exe Steam (Ghidra + vérification octet par octet) : `Gateway::AddTag` 8 arguments (rva `0x3A320`), `RemoveTag(TagUID)` (`0x2AF60`), `g_Gateway` (pointeur, `0x1D3E278`), `g_VirtualReader` (`0x1E1CEB8`, avatar courant à `+0x2C`), les six `Gateway::Write*` par UID (`0x2A2A0`…`0x2A5B0`). Le lecteur virtuel PC lui-même passe par `RemoveTag(id)` puis `AddTag(id, id, antenne 0, …)` (`ChangeAvatar`, `0x773060`). Notes : AUDIT.md §6.
2. **CrabeLoader** : `EngineGateway` (`infrastructure/engine_gateway.*`) ; adresses dans le profil du jeu, toutes vérifiées par leurs octets au démarrage (refus sinon) ; appels sous garde SEH ; hooks des six `Write*`, filtrés sur les UID ajoutés par CrabeLoader. Natives `_gatewayAddTag`, `_gatewayRemoveTag`, `_gatewayVirtualAvatar`, `_gatewayPollWrite` ; API `Crabe.Gateway` (`src/api/25b_gateway.lua`), événement `gatewayTagWrite(uid, field, value)`.
3. **Mod** (`figure_progress.lua` réécrit) : figurine posée sur J1 → retrait de l'avatar du lecteur virtuel, `AddTag(UID réel, SKU, antenne 0, XP, niveau, date, actions)` + compétences ; le jeu tient alors **sa propre fiche** pour cette figurine. Figurine retirée → `RemoveTag`, puis l'avatar du lecteur virtuel est remis. Quand le jeu enregistre la fiche, ses écritures sont regroupées (1 s de calme) puis envoyées à la figurine **si l'écriture est activée** dans le menu ; une remise à zéro (chemin « ClearOwner ») n'est jamais recopiée ; le propriétaire n'est jamais écrit. Figurine virtuelle, ou pont absent : ancien comportement (`Game.SetCharacter`).
4. La logique de fusion (montée de niveau par Lua, achat des compétences) est supprimée ; `figure_skills.lua` et son générateur sont retirés du dépôt (`git rm`).
5. **Nettoyage (16 h 30)** : code, logs, menu et docs en anglais ; commentaires uniquement au-dessus des fonctions (3 phrases max) ; `watch` explicite (le personnage du lecteur virtuel remis n'est plus surveillé) ; lecture hexadécimale sûre dans les natives. Docs : `CrabeLoader/docs/guides/portal.md`, `crabe_api.def.lua`, checklist manuelle, README du mod réécrit.

**Vérifié hors jeu :** compilation sans avertissement, `test_portal_write` 18/18, tests Lua de CrabeLoader 103/103, simulation du flux du mod (pose, enregistrement, remise à zéro ignorée, retrait, figurine virtuelle).

**À observer au premier test (écriture désactivée)** dans `loader.log` : `EngineGateway: resolved`, `tag 04685c82173f80 … added`, le personnage joué devient Joy avec **niveau 9 et ses 3 compétences** (et non la progression du lecteur virtuel), puis les lignes `the game saved level … ; writing to figures is off (menu)` après un gain d'XP. Inconnues : le jeu prend-il la pose immédiatement (hub, Toy Box, playset) ; le lecteur virtuel remet-il son avatar dans notre dos ; à quel moment le jeu enregistre la fiche.

---

## 4. Reste à faire

1. **Premier test en jeu de la version « une fiche par figurine »** (§3), écriture désactivée (lancement soumis à l'accord de Lucas).
2. Premier essai d'écriture réelle sur Joy (menu « Save progress to figures »), seulement si le test 1 est bon et avec l'accord explicite de Lucas ; la sauvegarde brute existe.
3. Mettre à jour `CrabeLoader/docs/crabe_api.def.lua` (natives et API `Crabe.Portal`) et régénérer `REPO_MAP.md`.
4. Confirmer visuellement les LED.
5. Portails HID et Xbox 360 : à tester dès qu'un portail est disponible.
6. Documenter dans le README du mod : WinUSB obligatoire pour la Xbox One, procédure Zadig.

---

## 5. Décisions et conventions

- Le thread de jeu ne touche jamais l'USB : tout passe par `PortalWorker` et une file d'événements.
- Aucun SKU, nom de personnage ni règle de jeu en C++ ; la logique de jeu reste dans le mod Lua.
- Slots Lua : 1 = Joueur 1, 2 = Joueur 2, 3 = Playset / hexagone, 0 = toutes les LED (antennes moteur : 1 = playset, 2 = J1, 3 = J2).
- La figurine n'est écrite que dans ses blocs de progression (secteurs 1-2, blocs 0-1), toujours dans la copie la plus ancienne, avec relecture.
- Rien n'est commité dans CrabeLoader (consigne : sur demande uniquement). Pas de `git init`.
- Versions des mods : toutes restent `1.0.0`.

---

## 6. Fichiers à connaître

| Quoi                                      | Où                                                                                                        |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Audit technique                           | `DisneyInfinityPortal\AUDIT.md`                                                                          |
| Mod                                       | `DisneyInfinityPortal\{portal.lua, figure_progress.lua, mod.json, deploy.ps1, README.md}`                |
| Générateur de la table des compétences | `DisneyInfinityPortal\tools\gen_figure_skills.lua`                                                       |
| C++ du portail                            | `CrabeLoader\{include,src}\infrastructure\portal\`                                                       |
| Pont vers le registre du moteur           | `CrabeLoader\{include,src}\infrastructure\engine_gateway.*`, `src\api\25b_gateway.lua`                 |
| API Lua                                   | `CrabeLoader\src\api\25_portal.lua`                                                                      |
| Natives                                   | `CrabeLoader\src\application\lua_natives.cpp` (chercher `_portal`)                                     |
| Tests                                     | `CrabeLoader\tests\cpp\{portal_probe.cpp, test_portal_write.cpp}`                                        |
| Sondes Python Xbox One                    | `research\reverse\portal\` (`first_contact.py`, `read_figures.py`, `dump_figure.py`, `gip_*.py`) |
| Bascule de pilote                         | `research\reverse\portal\switch_driver.ps1`                                                              |
| Source du moteur                          | `search_code.py` → `Octane/Code/Engine/LowLevel/Platform/Gateway/`                                    |
| DLL déployée / sauvegarde               | `bink2w32.dll` / `bink2w32.dll.bak_pre_portal_20261014` (dossier du jeu)                               |
| Log du jeu                                | `D:\SteamLibrary\steamapps\common\Disney Infinity 3.0 Gold Edition\loader.log`                           |
