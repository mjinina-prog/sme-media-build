# sme-media-build

Recette de construction des bibliothèques média de **SME Subtitle Editor** pour Windows x64 :

- **FFmpeg 8.1** (branche `release/8.1`, commit épinglé), en **DLL partagées**, réduit par une **liste d'autorisation** :
  `--disable-everything --disable-autodetect`, puis chaque démultiplexeur, décodeur, parseur, hwaccel et filtre nommé,
  avec sa raison (`recipe/ffmpeg-allowlist.sh`). **Aucun encodeur, aucun muxer.** Pas de `--enable-gpl`,
  pas de `--enable-nonfree`, pas de `--enable-version3` : FFmpeg reste sous **LGPL 2.1 ou ultérieure**.
  Bibliothèques externes : dav1d, zlib, nv-codec-headers (en-têtes seulement).
- **libmpv** (`libmpv-2.dll`), `-Dgpl=false` (LGPL 2.1 ou ultérieure), **liée dynamiquement à ces DLL FFmpeg**,
  avec LuaJIT, libass (FreeType, FriBidi, HarfBuzz, DirectWrite), libplacebo et Direct3D 11 (shaderc, SPIRV-Cross).
- **PyAV 18.0.0** compilé depuis la source contre **les mêmes DLL**, livrées dans le wheel **sous leur nom d'origine**
  (`avcodec-62.dll`…), pour qu'un processus qui charge libmpv et PyAV n'en charge qu'**une copie**.

## Ce qui garantit la licence

Aucune étiquette ne fait foi. Le workflow **refuse** une construction quand :

- une chaîne interdite apparaît dans une DLL, un EXE ou un `.pyd` (FFTW, chromaprint, zvbi, aribb24, libgme,
  x264/x265, `--enable-gpl`, `--enable-nonfree`, `--enable-version3`, étiquette FFmpeg « GPL »). Seules exceptions,
  citées une à une avec leur source dans `recipe/audit.py` : les chaînes par lesquelles le **décodeur** H.264 de FFmpeg
  et mpv reconnaissent les flux produits par d'anciennes versions de x264, et deux étiquettes FourCC de la table AVI ;
- la **carte d'édition de liens** montre une bibliothèque statique hors de la liste autorisée ;
- la configuration de mpv embarquée ne porte pas `-Dgpl=false` ;
- la **table d'import** d'un binaire nomme une DLL que Windows ne fournit pas et que la release ne livre pas
  (`libstdc++-6.dll`, `libwinpthread-1.dll`…), ou une DLL FFmpeg renommée ; ou libmpv n'importe pas les DLL FFmpeg ;
- l'horodatage PE d'une DLL construite ici n'est ni 0 ni `SOURCE_DATE_EPOCH`.

Voir `recipe/audit.py`. Les cartes d'édition de liens, l'inventaire tiré de ces cartes et le rapport de balayage
sont publiés avec chaque release.

## Reproduire

Toutes les entrées sont épinglées dans `pins.env` : commits de chaque composant, digest de l'image de la chaîne d'outils.

1. **Chaîne d'outils** — l'image `ghcr.io/btbn/ffmpeg-builds/base-win64` (Ubuntu + crosstool-NG `x86_64-w64-mingw32`,
   sans aucune bibliothèque), lue **par digest** : `recipe/run-build.sh` la tire du miroir
   `ghcr.io/mjinina-prog/sme-media-build/base-win64` tant qu'il sert ce digest, sinon de l'image amont, et vérifie
   son identifiant (`TOOLCHAIN_IMAGE_ID` de `pins.env`) avant de construire.
   Depuis le 2026-09-27, ce dépôt **ne publie plus l'image et ne la met plus en miroir** : un paquet créé par le
   workflow d'un dépôt public hérite de sa visibilité, et un paquet public ne redevient jamais privé. Le miroir déjà
   créé sert tant qu'il existe. La **copie de référence** de l'image (`docker save`, zstd) est tenue hors ligne
   par le mainteneur ; son empreinte est `TOOLCHAIN_ARCHIVE_SHA256` (`pins.env`). Pour construire à partir d'elle :
   `IMAGE_ARCHIVE_DIR=<répertoire de l'archive> bash recipe/run-build.sh`.
2. **Sources** — `recipe/fetch-sources.sh out/sources` récupère chaque composant à son commit et en fait une archive.
3. **Construction** — `recipe/run-build.sh` exécute `recipe/build-all.sh` dans l'image.
4. **PyAV** — `pyav/build_pyav.py` (Windows, MSVC).

Le workflow `.github/workflows/build.yml` enchaîne ces étapes (déclenchement manuel).

## Source correspondante

Chaque release contient les archives de **chaque composant au commit utilisé**, cette recette, le workflow,
les références de la chaîne d'outils (`TOOLCHAIN.txt`) et la liste des modifications apportées aux sources à la
construction (`MODIFICATIONS.txt`). C'est l'offre de source des bibliothèques LGPL livrées (LGPL-2.1 § 4 et § 6).
La chaîne d'outils elle-même (compilateur, éditeur de liens) n'en fait pas partie.

## Ce dépôt ne contient pas

- de fichier média client : les contrôles sur échantillons se font hors de ce dépôt ;
- le code de SME Subtitle Editor.

## Licences

- `recipe/cross-mingw64.meson` et `recipe/toolchain-mingw64.cmake` sont dérivés de fichiers de
  [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds) (licence MIT, texte dans `third_party/BtbN-FFmpeg-Builds.LICENSE`).
- Les autres fichiers de ce dépôt (recette, scripts, workflow) sont sous licence MIT, © 2026 Voicing Crew :
  texte dans `LICENSE`.
- Les composants construits gardent leur licence ; l'inventaire de chaque release les liste.
