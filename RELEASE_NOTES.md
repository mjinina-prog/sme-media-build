Construction de sme-media-build. Commits et digests : voir `pins.env` au commit de la release.

Contenu :
- `sme-media-*-win64-runtime.tar.xz` : les huit DLL (FFmpeg 8.1 partagé, libmpv-2.dll) et leurs licences ;
- `sme-media-*-win64-dev.tar.xz` : en-têtes, bibliothèques d'import, pkg-config ;
- `av-*.whl` : PyAV 18.0.0 compilé contre ces DLL, livrées sous leur nom d'origine ;
- `sme-media-*-maps.tar.xz`, `inventory.*`, `scan.json` : cartes d'édition de liens, inventaire lié, balayage ;
- `sme-media-*-source.tar` : source correspondante (chaque composant au commit, recette, workflow) ;
- `base-win64.docker.tar.zst.part-*` : image de la chaîne d'outils (`docker save`), restauration :
  `cat base-win64.docker.tar.zst.part-* | zstd -d -c | docker load`.

Empreintes : `SHA256SUMS`.
