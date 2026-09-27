Construction de sme-media-build. Commits et digests : voir `pins.env` au commit de la release.

Statut : @STATUT@

Contenu :
- `sme-media-*-win64-runtime.tar.xz` : les huit DLL (FFmpeg 8.1 partagé, libmpv-2.dll) et leurs licences ;
- `sme-media-*-win64-dev.tar.xz` : en-têtes, bibliothèques d'import, pkg-config ;
- `av-*.whl` : PyAV 18.0.0 compilé contre ces DLL, livrées sous leur nom d'origine ;
- `sme-media-*-maps.tar.xz`, `inventory.*`, `scan.json` : cartes d'édition de liens, inventaire lié, balayage ;
- `sme-media-*-source.tar` : source correspondante (chaque composant au commit, recette, workflow), avec
  `TOOLCHAIN.txt` (chaîne d'outils) et `MODIFICATIONS.txt` (modifications apportées aux sources).

Chaîne d'outils : son image n'est pas publiée. `TOOLCHAIN.txt` la nomme par digest et par l'empreinte de sa copie
de référence.

Modification des sources de mpv (LGPL-2.1, § 2 b) : à la construction, la recette récrit le fichier `MPV_VERSION` de
mpv, dont la ligne « 0.41.0-UNKNOWN » devient « 0.41.0-dev-g » suivi des neuf premiers caractères du commit de mpv,
pour que libmpv nomme son commit. C'est la seule modification d'un fichier de mpv ; elle est décrite, avec la seule
autre retouche de la recette (un fichier pkg-config de LuaJIT), dans `MODIFICATIONS.txt`.

Empreintes : `SHA256SUMS`.
