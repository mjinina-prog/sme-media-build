Construction de sme-media-build. Commits et digests : voir `pins.env` au commit de la release.

Statut : @STATUT@

Contenu :
- `sme-media-*-win64-runtime.tar.xz` : les huit DLL (FFmpeg 8.1 partagé, libmpv-2.dll), avec les textes de licence
  de mpv et de FFmpeg ; pas encore les notices des autres composants liés, que liste `inventory.md` ;
- `sme-media-*-win64-dev.tar.xz` : en-têtes, bibliothèques d'import, pkg-config ;
- `av-*.whl` : PyAV 18.0.0 compilé contre ces DLL, livrées sous leur nom d'origine ;
- `sme-media-*-maps.tar.xz`, `inventory.*`, `scan.json` : cartes d'édition de liens, inventaire lié, balayage ;
- `sme-media-*-meta.tar.xz` : journaux de configuration, relevé de la chaîne d'outils, options de construction,
  tables d'import ;
- `sme-media-*-source.tar` : source correspondante (chaque composant au commit, recette, workflow), avec
  `TOOLCHAIN.txt` (chaîne d'outils) et `MODIFICATIONS.txt` (modifications apportées aux sources).

Chaîne d'outils : son image n'est pas publiée. `TOOLCHAIN.txt` la nomme par digest et par l'empreinte de sa copie
de référence.

Modification des sources de mpv (LGPL-2.1, § 2 b) : à la construction, la recette récrit le fichier `MPV_VERSION` de
mpv, dont la ligne « 0.41.0-UNKNOWN » devient « 0.41.0-dev-g » suivi des neuf premiers caractères du commit de mpv,
pour que libmpv nomme son commit. C'est la seule modification d'un fichier de mpv. Un seul autre fichier des sources
est modifié : `etc/luajit.pc` de LuaJIT, un fichier pkg-config. Les deux modifications sont décrites dans
`MODIFICATIONS.txt`.

Empreintes : `SHA256SUMS`.
