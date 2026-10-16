# AUDIT TECHNIQUE COMPLET — Sous-système Portail Disney Infinity (DIM2)

**Dernière mise à jour :** 14 octobre 2026 (soir)
**Cible :** Disney Infinity 3.0 Gold Edition (PC Steam, Win32 x86, DirectX 11)
**Projets concernés :** `CrabeLoader` (branche locale `feature/portal-support`, jamais poussée), `DisneyInfinityPortal` (`mods\disneyinfinityportal\`), outils de sonde dans `research\reverse\portal\`
**Objectif :** un mod qui fait fonctionner **tous** les portails physiques (PS3/PS4/Wii/Wii U/PC, Xbox 360, Xbox One).

> Ce document remplace la première version de l'audit. Plusieurs affirmations de la version précédente étaient **fausses** (voir §10, « Corrections »). L'état d'avancement et la suite sont dans `STATUS.md`.
>
> **Xbox One : fonctionne** (validé en jeu le 14/10). Canal Disney = message GIP `0x21` après le handshake de sécurité v1, terminé par un COMPLETE envoyé sur l'ACK de la requête `0x08` (§5). La progression des figurines est lue, et écrite à la manière de la console (§3.7) ; l'écriture est désactivée tant que la version « une fiche par figurine » (§6) n'est pas prête.

---

## 1. Contexte

L'édition PC « Gold » ne gère plus les portails USB physiques : le matériel `Gateway` est remplacé par un menu virtuel (`VirtualReaderPC`, `TOYBOX_TOGO`). Le code source du moteur (Octane) contient pourtant tout le protocole, y compris les pilotes de chaque plateforme (`Platform/Gateway/{pc,x360,xb1,ps3,ps4,...}`), et le simulateur logiciel (`SoftSim`) que le jeu PC utilise à la place du matériel.

Le but est de lire les vrais portails depuis CrabeLoader (C++), d'exposer les figurines à Lua (`Crabe.Portal`), et de laisser le mod `DisneyInfinityPortal` décider quoi en faire.

---

## 2. Matériel de test

Seul portail disponible : **Xbox One `INF-8037059`** (PDP / Disney Interactive).

| Élément | Valeur |
|---|---|
| VID / PID | `0x0E6F` / `0x0229` |
| N° de série USB | `0000359F89AE3D30` |
| Classe / sous-classe / protocole | `0xFF` / `0x47` / `0xD0` (GIP) |
| Endpoints | `0x81` IN interrupt 64 o, `0x02` OUT interrupt 64 o |
| Pilote d'origine | `dc1-controller.sys` (pile GIP de Windows) |
| Pilote actuellement installé | **WinUSB** (via Zadig), obligatoire. Le pilote Xbox d'origine (`dc1-controller`) ne rend le socle accessible ni à `Windows.Gaming.Input.Custom` ni à GameInput 3.5 (testé le 14/10 : impasse) |
| Chemin d'interface WinUSB | `\\?\usb#vid_0e6f&pid_0229#0000359f89ae3d30#{4f97b9a4-b588-4f4f-89e7-f92f5ecc2eb0}` |

Aucun portail PS3/PC (HID) ni Xbox 360 n'est disponible : ces deux chemins sont écrits d'après le code source du moteur mais **non testés sur matériel**.

Tableau des révisions :

| Modèle | VID / PID | Interface | Sécurité | Prise en charge PC |
|---|---|---|---|---|
| PS3 / PS4 / Wii / Wii U / PC | `0E6F:0129` | USB HID pur | aucune | Fonctionne sans pilote (HID Windows) |
| Xbox 360 `INF-8032385` | `24C6:FA00` | USB vendeur (protocole XInput « Beyond ») | aucune connue | WinUSB (Zadig) requis |
| Xbox One `INF-8037059` | `0E6F:0229` | GIP (Game Input Protocol) | authentification GIP v1 (RSA) | WinUSB (Zadig) + handshake GIP — **validé** |

---

## 3. Protocole Disney « Gateway » (vérifié dans la source du moteur)

Source : `Octane/Code/Engine/LowLevel/Platform/Gateway/` (`GatewayPlatformBase.cpp/.h`, `Gateway.cpp`, `pc/`, `x360/`, `xb1/`, `SoftSim/`, `Aes128.cpp`, `crc32.cpp`). Chercher avec `search_code.py`.

### 3.1 Trames (toutes plateformes : 32 octets)

- **Requête hôte → base** : `[0xFF, len, cmd, id, données…, checksum]`
  - `len` = 2 + nombre d'octets de données (commande + id + données).
  - `checksum` = somme des octets précédents modulo 256, à l'indice `len + 2`.
  - `id` = compteur de requête, renvoyé dans la réponse.
- **Réponse base → hôte** : `[0xAA, len, id, données…, checksum]`
  - Lecture de bloc : `[AA, 12, id, statut, 16 octets, cks]` (statut 0 = OK).
  - UID : `[AA, 09, id, statut, 7 octets d'UID, cks]` (statut `0x80` = tag introuvable).
  - Réveil : plateforme `[3..4]`, matériel `[5..6]`, protocole `[7..8]`, firmware `[9..10]`, UID de base `[11..22]`.
  - Liste des tags : `len = 1 + 2n`, entrées `[(antenne<<4)|LTI, type]` à partir de l'indice 3 (**pas d'octet de statut**, vérifié sur matériel).
  - Écriture de bloc (`0xA3`) : `[AA, 02, id, résultat]` ; `0x00` OK, `0x80` tag retiré, `0x81` accès, `0x82` authentification, `0x84` erreur d'écriture, `0x86` secteur/bloc invalide (`GatewayPlatformBase`).
- **Notification asynchrone** : `[0xAB, 04, antenne, type, LTI, changement, cks]`, changement `0` = pose, `1` = retrait.
- Les trames reçues dont l'en-tête est autre que `0xAA`/`0xAB` (« auto-response ») sont ignorées par le moteur.

### 3.2 Commandes

| Code | Commande | Données |
|---|---|---|
| `0x80` | Réveil | `"(c) Disney 2013"` (15 o, len `0x11`) |
| `0x81` | Seed | valeur salée 8 o (sécurité anti-triche du jeu, non nécessaire pour lire les figurines) |
| `0x83` | Challenge | aucune |
| `0x90` | LED (une) | index, R, G, B |
| `0x95` | LED (toutes) | 3 × `[actif, R, G, B]`, len `0x0E` |
| `0xA1` | Liste des tags | aucune |
| `0xA2` | Lecture de bloc | LTI, secteur, bloc (len 5) |
| `0xA3` | Écriture de bloc | LTI, secteur, bloc, 16 o |
| `0xB4` | UID du tag | LTI (len 3) |
| `0xB5` | Intervalle de scan | octet |

### 3.3 Antennes et LED (**correction importante**)

Dans le moteur (`Gateway::MapRawAntennaIndexToGame`) : **antenne 1 = Playset (hexagone), 2 = Joueur 1, 3 = Joueur 2.**
Le jeu pilote les LED avec la commande `0x95` et un masque : **bit 0 (1) = playset, bit 1 (2) = joueur 1, bit 2 (4) = joueur 2.**
Convention Lua conservée : slot 1 = J1, 2 = J2, 3 = Playset / hexagone, 0 = toutes.

### 3.4 Initialisation du moteur (`GatewayPlatformBase::Update`)

1. `Wake` (réponse attendue ; renvoyé toutes les ~3 s sur PC).
2. `SetTagScanInterval(0xFF)` : contourne un bug firmware (compteur signé), attendre ~1 s.
3. `SetTagScanInterval(1)` (**3 sur Xbox One**, contrainte FCC).
4. Seed + Challenge périodique (tous les 5 s) : sécurité propre au jeu.
5. En fonctionnement : `ReadTagList` toutes les 2 s pour auditer les tags.
Sur insertion (`0xAB`) : `GetTagUID(lti)` puis lecture du bloc d'identité.

### 3.5 Bloc d'identité d'une figurine (**corrections importantes**)

- Position : **secteur 0, bloc 1**.
- Clé AES-128 : `SHA1_LSB( cléBase(16) ‖ "(c) Disney 2013"(15) ‖ UID(7, big-endian) )`, 16 premiers octets.
  - `cléBase = AF 62 D2 EC 04 91 96 8C C5 2A 1A 71 65 F8 65 FE`.
  - `SHA1_LSB` = SHA-1 standard dont **chaque mot de 32 bits est écrit octet de poids faible en premier**.
- Chiffrement : **AES-128-ECB**, un bloc.
- Bloc déchiffré : SKU `[0..3]` (BE), date de fabrication `[4..7]`, drapeaux `[7]` (bit 1 = clé de contenu requise), version `[8..9]` (**`3`** sur Joy, pas `1`), **magic `[10..11]` = `0xD11F`**, **CRC-32 de `[0..11]` en `[12..15]`** (BE).
- Vérifié sur la vraie Joy : SKU `1000216` = sku_id du jeu (`OUT_Joy`), donc directement utilisable par `Game.SetCharacter`.
- CRC-32 du moteur : polynôme réfléchi `0xEDB88320`, valeur initiale **0**, pas de XOR final.
- Autres blocs : voir §3.7. Le secteur 0 bloc 2 n'est **pas** une clé de déchiffrement des données : c'est une clé de contenu (DLC) contrôlée par checksum, sans CRC.

### 3.6 Enveloppes de transport par plateforme

| Plateforme | Écriture | Lecture |
|---|---|---|
| **PC / HID** (`pc/Gateway.pc.cpp`) | rapport HID : octet 0 = id de rapport `0`, puis 32 o ; taille `OutputReportByteLength` | `InputReportByteLength` ; trame à partir de l'octet 1 |
| **Xbox 360** (`x360/Gateway.360.cpp`) | `XInputBeyondSetRaw(32, buf)` avec `buf[0]=0x0B`, `buf[1]=0x15`, trame à partir de l'octet 2 | `XInputBeyondGetRaw` ; trame à partir de l'octet 2 |
| **Xbox One** (`xb1/Gateway.xb1.cpp`, pilote `InfinityBaseDriver/`) | `IBase::SendRequest(32 octets)` → message GIP **`0x21`**, non système (`GenericGip.h`) | événement `BaseReport` ← message GIP `0x21` |

Sur Xbox One, c'est l'API console qui encapsule les 32 octets dans GIP ; sur PC CrabeLoader le fait lui-même (§5), sur WinUSB.

---

### 3.7 Données de progression d'une figurine (vérifié dans la source et sur Joy)

Figurines personnage : MIFARE Mini, **5 secteurs** de 4 blocs (bloc 3 = trailer, jamais écrit). Tous les blocs de données utilisent la même clé AES que le bloc d'identité, avec CRC-32 moteur des octets `[0..11]` en `[12..15]` (BE). Un bloc dont les 16 octets **chiffrés** sont nuls = jamais écrit. Source : `Gateway.cpp` (`DecryptAndCheckData :1032-1071`, lecture `:1339-2207`, `FlushTagData :2604-2812`), `IGP.h`, `IGPGameFlow.cpp`.

| Bloc | Contenu déchiffré |
|---|---|
| S1B0 / S2B0 — expérience | XP **dans le niveau courant** u32 BE `[0..3]` (`IGPTagData::m_experience` tronqué) · niveau `[4]` · dernière partie u32 BE `[5..8]` · drapeaux d'action `[9]` · `[10]` inutilisé · séquence `[11]` · CRC |
| S1B1 / S2B1 — compétences | bits `[0..7]` (bit n = `octet[n/8] & (1 << n%8)`, bit 63 jamais utilisé, max livré BIT57) · `[8..10]` = 0 · séquence `[11]` · CRC |
| S3B0 / S3B1 — SWID Disney | moitiés du SWID `[0..7]` · propriétaire u24 `[8..10]` (identique dans les deux) · séquence `[11]` · CRC |

- **Double copie** : expérience et compétences existent en secteur 1 **et** 2, chacune avec sa séquence. Copie courante (`CompareTimeStamps :469-479`) : `0x00` bat `0xFF`, sinon la plus grande ; deux à 0 → S1 ; égales non nulles → S2. CRC invalide → l'autre copie.
- **Écriture console** : dans la copie **non courante**, séquence + 1 (u8, `0xFF → 0x00`), CRC, AES, commande `0xA3 [lti, secteur, bloc, 16 octets]`. Pas de relecture côté moteur ; jusqu'à 5 tentatives.
- **Quand** (`SaveIGPByPlayerNum`) : montée de niveau, achat/remboursement de compétence (immédiat), gain d'XP ≥ 1 (au plus toutes les 10 s, `TAG_DATA_FLUSH_TIME`), chargement de l'avatar, prise de possession. Rien au retrait de la figurine.
- **Dernière partie** : date locale empaquetée `(an-2013)<<26 | mois<<22 | jour<<17 | heure<<12 | minute<<6` (`AvatarSpawning::GetCurrentDateAsUInt`). Joy : `0x1874AA00` = 26/01/2019 10:40.
- **Drapeaux d'action** (`IGP.h:27-40`) : 0x01 bâtiment, 0x02 événement gagné, 0x04 course gagnée, 0x08 ennemi vaincu, 0x10 étoile, 0x20 joué sur portable, 0x40 niveau max, 0x80 joué dans IN2. Fusion à l'écriture : `(profil & SaveData) | (tag & ~SaveData)`.
- **Bits → compétences** : table `BitMap = { BITn = { Upgrade = "…" } }` du fichier gamedb de chaque personnage (`ProgressionTable.Name` = `ProgressionTree` de la ligne VirtualReader). Les points de compétence ne sont pas stockés : niveau − coût des bits.
- **Lecture console** (`IGPGameFlow::LoadIGP :11645-11710`) : la figurine l'emporte seulement si son niveau est plus haut (ou égal avec plus d'XP) ; dates : la plus récente ; drapeaux : OU.
- **Joy (UID `04685c82173f80`)** : S1 courant (séq. `0x48` contre `0x47`), niveau 9, 102 XP, drapeaux `0x80`, compétences bits 0, 18, 19 = JOY_HEALTH1, JOY_PARRY, JOY_SPECIAL_UNLOCKED ; SWID vide, propriétaire `aae4f8`. Tous les CRC valides.

## 4. État du code C++ (CrabeLoader, branche locale `feature/portal-support`, non commitée)

**Compile** (MSVC, Win32) depuis le 14/10 : `bink2w32.dll`, `portal_probe.exe` (worker réel en console), `test_portal_write.exe` (tests hors ligne, 18/18).

| Fichier | Rôle |
|---|---|
| `portal_types.hpp` | `Report` (32 o), `PortalType`, `FigureProgress` (XP, niveau, date, drapeaux, bits), `PortalTagEvent` (slot, SKU, UID, progression optionnelle), `PortalStatus` |
| `portal_crypto.hpp/.cpp` | Windows CNG : clé par figurine, `DecodeIdBlock`, `DecryptDataBlock` (AES + CRC), `SealDataBlock` (CRC + AES) |
| `portal_protocol.hpp/.cpp` | `DisneyBaseProtocol`, sans E/S : réveil, scan, liste des tags, UID, identité, **4 blocs de progression**, choix de la copie courante, **`WriteProgress`** (copie ancienne, séquence + 1, relecture et comparaison ; seuls S1-S2 / B0-B1 autorisés) |
| `portal_transports.cpp` | HID, Xbox 360 (WinUSB), découverte (Xbox One : WinUSB requis, sinon diagnostic Zadig) |
| `portal_transport_gip.cpp` | Xbox One : trames GIP (varint, en-tête pair, chunks + ACK), handshake v1 (RSA PKCS#1, SHA-256, P_SHA256), COMPLETE sur l'ACK de la requête `0x08`, rapports Disney sur `0x21` |
| `usb_device.hpp/.cpp` | WinUSB ; présence WinUSB détectée par une interface **active** (les GUID laissés par Zadig survivent à un changement de pilote) |
| `portal_worker.hpp/.cpp` | thread dédié : découverte, session, reconnexion ; `SetLed`, `WriteProgress` sous verrou |
| `portal_service.hpp/.cpp` | façade côté jeu : slots, file d'événements, portail virtuel |

Natives : `_portalIsConnected`, `_portalGetStatus` (+ type), `_portalSetLed`, `_portalPollEvent` (type, slot, SKU, UID hex, puis niveau, XP, bits hex, drapeaux, date ; nil sans progression), `_portalWriteProgress(slot, niveau, xp, bitsHex, drapeaux, date)`, `_portalEmulatePlace/Remove`.

API Lua (`src/api/25_portal.lua`) : primitives seulement ; événements `portalFigurePlaced(slot, sku, uid, progress)` et `portalFigureRemoved(slot, uid)` ; `Crabe.Portal.writeFigureProgress(slot, progress)`.

Supprimés en cours de route : `portal_driver.*` (ancienne implémentation), `portal_transport_wgi.cpp` (essai `Windows.Gaming.Input`, impasse).

Reste côté C++ : version « une fiche par figurine » (§6), mise à jour de `docs/crabe_api.def.lua` et `REPO_MAP.md`.

## 5. Xbox One : GIP, résultats des sondes sur le vrai matériel

Outils : `research\reverse\portal\` (Python pur + `ctypes`, aucun module externe sauf `cryptography` pour l'ECDH) — `winusb_dev.py`, `gip_probe.py`, `gip_auth.py`, `gip_auth_timing.py`, `gip_auth_variants.py`, `gip_auth_timing.py`.

### 5.1 Format GIP (confirmé sur le matériel)

Trame : `[commande, options, séquence, longueur (varint LEB128), (offset de chunk si CHUNK), données]`.
Options : `0x10` accusé demandé, `0x20` interne/système, `0x40` début de chunk, `0x80` chunk, quartet bas = id client (0).
Longueur d'en-tête paire (padding `0x80 0x00`). Séquence : par commande, de 1 à 255, jamais 0.
Commandes système : `01` ACK, `02` ANNOUNCE, `03` STATUS, `04` IDENTIFY, `05` POWER, `06` AUTHENTICATE, `07` clé virtuelle, `08` audio, `0A` LED, `0B` HID, `0C` firmware, `1E` numéro de série, `20` entrée, `60` audio.
ACK : header `01 20 <séquence du message acquitté> 09`, données `[00, cmd, 0x20, longueur LE16 reçue, 00 00, restant LE16]`.
Chunks reçus : le premier porte `0xF0` avec le total en offset, les suivants `0xA0`/`0xB0`, puis un chunk vide dont l'offset est la taille totale. Chaque chunk marqué `0x10` doit être acquitté.

### 5.2 Ce qui fonctionne

- **ANNOUNCE** reçu (toutes les ~500 ms) : id d'appareil `30 3D AE 89 9F 35 00 00`, VID `0E6F`, PID `0229`, versions firmware/matériel.
- **IDENTIFY** (`04 20 seq 00`) → descripteur de 142 octets en 3 chunks (ACK testé). Le socle accepte l'ACK que j'ai construit.
- **POWER ON** (`05 20 seq 01 00`) → ACK de l'appareil.
- Écriture WinUSB OK sur l'endpoint `0x02`, lecture sur `0x81`.

### 5.3 Descripteur décodé

```
10 00 01 00 00 00 00 00 00 00 00 00 00 00 8E 00 66 00 16 00 1B 00 1C 00 23 00 29 00 45 00
00 00 00 00 00 00 01 01 00 00 00 00 06 01 02 03 04 06 1F 05 01 04 05 06 1F 01 19 00
"Disney.Xbox.Infinity.Base" 02 3C 17 0D E9 9B 30 A6 41 A4 77 82 6E 2C 97 D8 82
56 FF 76 97 FD 9B 81 45 AD 45 B6 45 BB A5 26 D6 01 17 00 21 20 00 01 00 18 00 …
```
- En-tête de 16 octets ; les décalages (u16 LE) sont relatifs au début des données (indice 16).
- Commandes émises par le socle : `01 02 03 04 06 1F` ; commandes reçues par le socle : `01 04 05 06 1F`.
- ~~`0x1F` est le canal Disney~~ : **faux**. Le canal est le message **`0x21`** (déclaré plus loin dans le descripteur : `… 21 20 00 01 00 18 00 …`), confirmé par `InfinityBaseDriver/GenericGip.h` et sur matériel. `0x1F` n'a jamais répondu.
- Classe : `"Disney.Xbox.Infinity.Base"` (le moteur filtre sur ce type).
- GUID d'interface : `E90D173C-309B-41A6-A477-826E2C97D882` (probablement `IBase`) et `9776FF56-9BFD-4581-AD45-B645BBA526D6` (`IController`).
- Aucune commande personnalisée déclarée dans la table « custom commands ».

### 5.4 Pourquoi rien ne marchait le matin, et la solution

1. **Mauvais canal** : les trames Disney étaient envoyées sur `0x1F`. Le bon canal est `0x21`, options `0x00`, 32 octets (`21 00 seq 20 <32 o>`), réponses sur `0x21` aussi.
2. **Handshake jamais terminé** : le firmware PDP n'envoie **jamais** de CLIENT_FINISH. Il répond à la requête `0x08` par un ACK GIP (`01 20 seq … 06 30 …`) puis un message `00 C2 00 03 00 00`. Windows envoie alors aussitôt le contrôle **COMPLETE** (`06 20 seq 02 | 01 00`). Les sondes redemandaient `0x08` en boucle : le socle restait bloqué (réponses vides `06 30 seq 00` ~1,18 s plus tard) jusqu'au débranchement.
3. Les codes `01`, `02`, `03` du champ « commande » des ACK de handshake sont un compteur d'étapes, pas des erreurs (contrairement à la lecture de `xone`).
4. **L'authentification est obligatoire** : sur un socle fraîchement rebranché, `0x21` sans authentification reste sans réponse.

Flux validé (v1, RSA) : IDENTIFY → POWER ON → HOST_HELLO (`0x01`, aléa 32 + 8 o + trailer 8) → ACK → requête CLIENT_HELLO (`0x02`, 80 o) → requête certificat (`0x03`, 1024 ; le socle renvoie 815 o, certificat « Xbox Accessories Class Prod CA 001 », RSA 2048) → HOST_SECRET (`0x05`, PMS 48 o chiffré PKCS#1, envoyé en chunks) → ACK → HOST_FINISH (`0x07`, PRF « Host Finished » sur SHA-256 de la transcription) → ACK → requête `0x08` → **ACK GIP → COMPLETE**. Le socle accepte le handshake sans être redébranché entre deux sessions.

### 5.5 Implémentation

- Python : `research\reverse\portal\first_contact.py` (session complète), `gip_auth.py`, `read_figures.py`, `dump_figure.py` (lecture seule, sauvegarde JSON), `noauth_test.py`.
- C++ : `portal_transport_gip.cpp` (§4). Test hors jeu `portal_probe.exe` puis **en jeu le 14/10 à 14:01** : authentification, réveil (plateforme `0x0200`, matériel 2.0, protocole 3.4, firmware 12.7), Joy détectée.
- Références lues (aucun code recopié) : `xone` (GPL, Linux), XboxHeadsetBridge (casque PDP), Microsoft MS-GIPUSB.

## 6. Intégration au jeu : ce qu'on sait

- Le jeu PC utilise `VirtualReaderPC` et le `Gateway` en mode simulé. Changer de personnage : `Game.SetCharacter(sku, "loadout", joueur)` (`VirtualReaderPC_SetCurrentCharacter` + `ActivateChanges`). Niveau : `Players_GetAvatarLevel(sku)`, `Players_AvatarLevelUp(joueur, sku)` (un niveau par appel, pas de descente). Compétences : `UI_GetSkillTreeGridData(joueur, grille)` et `UI_GetItemArgumentsForPlayer("SkillTree_IN3", joueur, "ispurchased"|"purchaseskill", case, grille[, true])`. Aucune native ne lit l'XP dans le niveau.
- **La sauvegarde range la progression par UID de figurine** : liste `IGPTagData` (`m_tagUID`, `m_characterId`, XP, niveau, bits…), recherche `IGP::AvatarInProfile(TagUID)` (`IGP.cpp:73`). Le lecteur virtuel pose de fausses puces avec `uid = id du personnage` (`g_Gateway.AddTag(id, id, 0,0,0,0,0,0)`, `VirtualReader.cpp:1166`).
- **Conséquence** : posée sous son vrai UID via `Gateway::AddTag(uid, id, antenne, xp, niveau, date, actions, propriétaire)` (`Gateway.cpp:7964`), une figurine physique aurait sa propre fiche, comme sur console. C'est la piste retenue pour remplacer la « fusion » du mod (`STATUS.md` §3). Reverse de l'exe Steam en cours ; non vérifié : présence de ce chemin dans l'exe, comportement de `LoadIGP` sur une puce logicielle (`m_progressionDataValid`), écran de sélection.

## 7. Mod `DisneyInfinityPortal` (état au 14/10 soir)

- Fichiers : `mod.json`, `portal.lua`, `figure_progress.lua`, `figure_skills.lua` (généré par `tools/gen_figure_skills.lua` : 169 arbres, tous les personnages jouables couverts), `deploy.ps1`. Commité par Lucas (`ae6042c`).
- `portal.lua` : à la pose sur J1/J2, LED (cyan / magenta, or pour l'hexagone) et `Game.SetCharacter` ; menu F5 « Portail Disney » : statut (avec progression lue), tests LED, figurines virtuelles choisies dans la liste des personnages, interrupteur d'écriture.
- `figure_progress.lua` : approche « fusion » (niveau PC monté jusqu'à celui de la figurine, compétences achetées 2,5 s après la pose, écriture périodique max(PC, figurine)). **Jamais exécutée en jeu ; écriture désactivée par défaut**, à remplacer par la version « une fiche par figurine ».
- Plus de SKU par défaut ni de spawn dans l'API : réglé.

## 8. Tests en jeu

**14/10, 14:01 (nouvelle version) :** socle authentifié au démarrage, Joy détectée sur l'antenne 2, `PortalService: figurine posée sur le slot 1 (SKU 1000216)`, mod : `Figurine posee sur Joueur 1 : Joy`. Retrait à 14:02:10 (à confirmer : geste volontaire ou faux retrait). Changement de personnage non observé (menu principal, pas d'avatar).

**Session précédente (ancienne version) :**

| Symptôme | Explication |
|---|---|
| « Le mod ne fait rien » | Il était chargé (`ModManager: [11/21] local.disneyinfinityportal 1.0.0 loaded`). Les logs sont dans `D:\SteamLibrary\steamapps\common\Disney Infinity 3.0 Gold Edition\loader.log` |
| « Pas de LED » | Le pilote refusait d'écrire sur un socle Xbox One non authentifié ; de toute façon les trames étaient des trames Disney brutes sans en-tête GIP, donc ignorées par le socle |
| « Il sait que mettre Anakin » | Le bouton de menu appelait `Crabe.Portal.placeVirtualFigure(1, 1000200)` (SKU d'Anakin) ; aucune figurine réelle ne pouvait être lue |

---

## 9. Outils et sources utiles

- Recherche dans le code du moteur : `python E:\Dev\DIM2\research\knowledge-base\search_code.py "<terme>"` (sous-commandes `def`, `show source:chemin:lignes`, `files`).
- Sondes USB (Python, pilote WinUSB requis) : `research\reverse\portal\first_contact.py` (session complète), `read_figures.py`, `dump_figure.py` (lecture seule + sauvegarde JSON), `gip_complete.py`, `noauth_test.py`, plus les anciennes `gip_probe.py`, `gip_auth*.py`.
- C++ : `CrabeLoader\build\Release\portal_probe.exe [secondes]`, `test_portal_write.exe`.
- Bascule de pilote : `research\reverse\portal\switch_driver.ps1 -To WinUsb|Xbox` (admin).
- Références externes (lecture seule) : spécification Microsoft MS-GIPUSB (publiée en 2024), notes communautaires de TheNathannator sur GIP, projet `xone` (`auth/auth.c`, `auth/crypto.c`, `bus/protocol.c`).

---

## 10. Corrections par rapport à la première version de cet audit

| Affirmation précédente | Réalité (source du moteur / mesure) |
|---|---|
| Magic du bloc d'identité `0x010B` aux octets 10-11 | **`0xD11F`** ; `0x01` est la *version* (octets 8-9) |
| Slot 1 = J1, 2 = J2, 3 = Playset d'après l'antenne | Antenne 1 = **Playset**, 2 = **J1**, 3 = **J2** |
| Notification de tag : `[AB, …, antenne=p[4], type=p[5], lti=p[6]]` | `[AB, 04, antenne=p[2], type=p[3], LTI=p[4], changement=p[5]]` |
| Réponses `0xAA` identifiées par la commande | Identifiées par l'**id de requête** `p[2]` |
| UID du tag fixe `04 12 34 56 78 9a bc` | UID réel par `GetTagUID (0xB4)` |
| « Le socle Xbox One est verrouillé matériellement, impossible » | Il parle GIP ; **le canal est la commande `0x1F`** ; seule l'authentification reste à franchir |
| Écrire des trames Disney brutes sur l'endpoint `0x02` | Il faut les encapsuler en GIP (`1F opts seq 20 <32 o>`) |
| Octets 10..11 = « magiques Disney » à `0x010B` | voir ci-dessus |
| Toute la cryptographie « validée » | Seul le découpage SHA-1/AES était cohérent avec la source ; aucun vecteur de test n'avait été exécuté. Les nouveaux tests sont à écrire (`STATUS.md`) |
| `Crabe.Portal.update()` de l'API fait le spawn | Déplacé dans le mod (fait) |
| Canal Disney Xbox One = GIP `0x1F` | **`0x21`** (`GenericGip.h`, vérifié sur matériel) |
| Le socle refuse l'authentification | Il l'accepte ; il fallait envoyer COMPLETE sur l'ACK de la requête `0x08` au lieu de redemander le CLIENT_FINISH |
| Version du bloc d'identité attendue = 1 | `3` sur Joy |
| Liste des tags avec octet de statut | Pas d'octet de statut |
| Secteur 0 bloc 2 = clé de déchiffrement des données | Clé de contenu (DLC) ; toutes les données utilisent la clé de la figurine |
| Le pilote Xbox de Windows suffirait (Windows authentifie) | Le socle n'est exposé ni à `Windows.Gaming.Input` ni à GameInput ; WinUSB obligatoire |
