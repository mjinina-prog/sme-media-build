#!/usr/bin/env bash
# build-all.sh — s'exécute DANS l'image base-win64 (chaîne crosstool-NG x86_64-w64-mingw32).
# L'image ne sert que de chaîne d'outils (DA-6) : chaque bibliothèque est compilée ici, depuis les archives
# de fetch-sources.sh, dans /work/prefix ; rien n'est pris dans /opt/ffbuild (vide dans cette image).
#
# Montages attendus : /recipe (ce dépôt, lecture seule) · /sources (archives, lecture seule) · /work (vide) · /out.
# Sorties (/out) : bin/ (DLL livrées, épurées de leurs symboles), unstripped/, probe/ffprobe.exe,
# dev/ffmpeg (en-têtes, .def, .dll.a, pkg-config), dev/libmpv, maps/ (cartes d'édition de liens), meta/, logs/.
set -euo pipefail
shopt -s nullglob

source /recipe/pins.env
source /recipe/recipe/ffmpeg-allowlist.sh

export SOURCE_DATE_EPOCH TZ=UTC LC_ALL=C.UTF-8
export GIT_CEILING_DIRECTORIES=/work
umask 022

T=x86_64-w64-mingw32
PREFIX=/work/prefix
SRC=/work/src
BLD=/work/build
OUT=/out
CROSS=/recipe/recipe/cross-mingw64.meson
CMAKE_TC=/recipe/recipe/toolchain-mingw64.cmake
JOBS="$(nproc)"

mkdir -p "$PREFIX"/lib/pkgconfig "$PREFIX"/include "$PREFIX"/bin "$SRC" "$BLD" /work/home \
         "$OUT"/bin "$OUT"/unstripped "$OUT"/probe "$OUT"/maps "$OUT"/meta "$OUT"/logs \
         "$OUT"/dev/ffmpeg/lib/pkgconfig "$OUT"/dev/libmpv/lib
export HOME=/work/home

# Environnement de compilation : posé ici, jamais hérité de l'image.
unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS PKG_CONFIG_PATH STAGE_CFLAGS STAGE_CXXFLAGS
export CC="$T-gcc" CXX="$T-g++" AR="$T-gcc-ar" RANLIB="$T-gcc-ranlib" NM="$T-gcc-nm" \
       STRIP="$T-strip" DLLTOOL="$T-dlltool" WINDRES="$T-windres" LD="$T-ld"
export PKG_CONFIG=pkg-config
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
export CFLAGS="-O2 -pipe -D_FORTIFY_SOURCE=2 -fstack-protector-strong -I$PREFIX/include"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-static-libgcc -static-libstdc++ -fstack-protector-strong -L$PREFIX/lib -Wl,--no-insert-timestamp"

group() { echo "::group::$*"; }
endgroup() { echo "::endgroup::"; }

extract() {  # extract <composant> [répertoire cible] : archive nommée par SOURCES.tsv, empreinte vérifiée
    # Recherche exacte sur la colonne « composant » : un motif de nom confondrait « libplacebo » avec
    # « libplacebo-fast-float » (« f » est un chiffre hexadécimal).
    local n="$1" dest="${2:-$SRC}" a h
    a="$(awk -F'\t' -v n="$n" 'NR > 1 && $1 == n { print $4 }' /sources/SOURCES.tsv)"
    h="$(awk -F'\t' -v n="$n" 'NR > 1 && $1 == n { print $6 }' /sources/SOURCES.tsv)"
    if [ -z "$a" ] || [ "$(printf '%s\n' "$a" | wc -l)" != 1 ] || [ ! -f "/sources/$a" ]; then
        echo "archive introuvable ou ambiguë pour $n dans SOURCES.tsv : ${a:-aucune}" >&2
        exit 1
    fi
    if [ "$(sha256sum "/sources/$a" | cut -d' ' -f1)" != "$h" ]; then
        echo "empreinte différente de SOURCES.tsv : $a" >&2
        exit 1
    fi
    mkdir -p "$dest"
    tar -xJf "/sources/$a" -C "$dest"
}

meson_static() {  # meson_static <src> <build> [options…]
    local s="$1" b="$2"
    shift 2
    meson setup "$b" "$s" --cross-file "$CROSS" --prefix="$PREFIX" --libdir=lib \
        --buildtype=release --default-library=static --wrap-mode=nofallback "$@"
    ninja -C "$b" -j"$JOBS"
    ninja -C "$b" install
}

record_toolchain() {
    # Relevé seulement : une commande absente ne doit pas arrêter la construction (set +e dans le sous-shell).
    (
    set +e +o pipefail
    {
        echo "# chaîne d'outils (relevé dans le conteneur)"
        echo "image: $TOOLCHAIN_MIRROR@$TOOLCHAIN_DIGEST"
        grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release || true
        "$T-gcc" --version | head -1
        "$T-ld" --version | head -1
        echo "mingw-w64 :"
        find /opt/ct-ng/"$T"/sysroot -name _mingw_mac.h -exec \
            grep -hE '#define __MINGW64_VERSION_(MAJOR|MINOR|BUGFIX|STATE)\b' {} + | sort -u
        printf 'thread model : '; "$T-gcc" -v 2>&1 | grep -i 'thread model' || true
        nasm -v
        meson --version | sed 's/^/meson /'
        cmake --version | head -1
        ninja --version | sed 's/^/ninja /'
        pkg-config --version | sed 's/^/pkg-config /'
        python3 --version
        make --version | head -1
        echo "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"
        echo "# bibliothèques C++ et fils d'exécution de la chaîne (statiques seules attendues)"
        find /opt/ct-ng -name 'libstdc++*' -o -name 'libwinpthread*' -o -name 'libpthread*' -o -name 'libgcc_s*' \
            -o -name 'libssp*' | sort
    } > "$OUT/meta/toolchain.txt" 2>&1
    )
    cat "$OUT/meta/toolchain.txt"
}

build_zlib() {
    group "zlib"
    extract zlib
    cd "$SRC/zlib"
    ./configure --prefix="$PREFIX" --static
    make -j"$JOBS"
    make install
    endgroup
}

build_dav1d() {
    group "dav1d"
    extract dav1d
    meson_static "$SRC/dav1d" "$BLD/dav1d" \
        -Denable_tools=false -Denable_tests=false -Denable_examples=false -Denable_docs=false \
        -Dxxhash_muxer=disabled
    endgroup
}

build_ffnvcodec() {
    group "nv-codec-headers"
    extract ffnvcodec
    make -C "$SRC/ffnvcodec" PREFIX="$PREFIX" install
    endgroup
}

build_ffmpeg() {
    group "FFmpeg"
    extract ffmpeg
    # Nom du répertoire = ffmpeg-<7 hex> : ffbuild/version.sh y lit le commit quand .git manque
    # (« Snapshots from gitweb »), d'où la version « 8.1.3-45e8e0a » sans toucher la source.
    local fsrc="$SRC/ffmpeg-${FFMPEG_COMMIT:0:7}"
    mv "$SRC/ffmpeg" "$fsrc"
    mkdir -p "$BLD/ffmpeg"
    cd "$BLD/ffmpeg"
    local enables=()
    local x
    for x in "${FF_PROTOCOLS[@]}"; do enables+=("--enable-protocol=$x"); done
    for x in "${FF_DEMUXERS[@]}"; do enables+=("--enable-demuxer=$x"); done
    for x in "${FF_DECODERS[@]}"; do enables+=("--enable-decoder=$x"); done
    for x in "${FF_PARSERS[@]}"; do enables+=("--enable-parser=$x"); done
    for x in "${FF_BSFS[@]}"; do enables+=("--enable-bsf=$x"); done
    for x in "${FF_HWACCELS[@]}"; do enables+=("--enable-hwaccel=$x"); done
    for x in "${FF_FILTERS[@]}"; do enables+=("--enable-filter=$x"); done
    local conf=(
        "$fsrc/configure"
        --prefix="$PREFIX"
        --target-os=mingw32 --arch=x86_64 --cross-prefix="$T-"
        --cc="$T-gcc" --cxx="$T-g++" --ar="$T-gcc-ar" --ranlib="$T-gcc-ranlib" --nm="$T-gcc-nm"
        --ld="bash /recipe/recipe/ldmap.sh $T-gcc"
        --pkg-config=pkg-config --pkg-config-flags=--static
        --extra-cflags="-I$PREFIX/include -D_FORTIFY_SOURCE=2 -fstack-protector-strong"
        --extra-ldflags="-L$PREFIX/lib -static-libgcc -fstack-protector-strong"
        --disable-everything --disable-autodetect
        --disable-network --disable-doc --disable-debug
        --disable-stripping
        --enable-shared --disable-static
        --disable-programs --enable-ffprobe
        --enable-w32threads
        --enable-zlib --enable-libdav1d
        --enable-d3d11va --enable-dxva2 --enable-ffnvcodec --enable-cuda --enable-nvdec
        "${enables[@]}"
    )
    printf '%q ' "${conf[@]}" > "$OUT/meta/ffmpeg-configure-command.txt"
    echo >> "$OUT/meta/ffmpeg-configure-command.txt"
    "${conf[@]}" | tee "$OUT/logs/ffmpeg-configure.txt" || { tail -200 ffbuild/config.log; exit 1; }
    cp ffbuild/config.log "$OUT/logs/ffmpeg-config.log"
    make -j"$JOBS"
    make install
    # Les .pc installés ne gardent pas Libs.private : libmpv lie FFmpeg par ses DLL, jamais ses dépendances.
    sed -i '/^Libs.private:/d' "$PREFIX"/lib/pkgconfig/lib{avcodec,avdevice,avfilter,avformat,avutil,swresample,swscale}.pc
    local m
    for m in $(find "$BLD/ffmpeg" -name '*.dll.map' -o -name 'ffprobe*.exe.map'); do
        cp "$m" "$OUT/maps/$(basename "$m")"
    done
    endgroup
}

build_freetype() {
    group "freetype"
    extract freetype
    meson_static "$SRC/freetype" "$BLD/freetype" \
        -Dbrotli=disabled -Dbzip2=disabled -Dharfbuzz=disabled -Dpng=disabled -Dzlib=disabled \
        -Dmmap=disabled -Dtests=disabled -Dhvf=disabled -Derror_strings=false
    endgroup
}

build_fribidi() {
    group "fribidi"
    extract fribidi
    meson_static "$SRC/fribidi" "$BLD/fribidi" -Ddocs=false -Dbin=false -Dtests=false
    # Liaison statique sous Windows : sans ce symbole, les en-têtes déclarent les fonctions en dllimport.
    sed -i 's/^Cflags:/Cflags: -DFRIBIDI_LIB_STATIC/' "$PREFIX/lib/pkgconfig/fribidi.pc"
    endgroup
}

build_harfbuzz() {
    group "harfbuzz"
    extract harfbuzz
    meson_static "$SRC/harfbuzz" "$BLD/harfbuzz" -Dauto_features=disabled \
        -Dfreetype=enabled \
        -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dchafa=disabled -Dpng=disabled -Dzlib=disabled \
        -Dicu=disabled -Dgraphite=disabled -Dgraphite2=disabled -Dfontations=disabled -Dgdi=disabled \
        -Ddirectwrite=disabled -Dcoretext=disabled -Dharfrust=disabled -Dkbts=disabled -Dwasm=disabled \
        -Draster=disabled -Dvector=disabled -Dgpu=disabled -Dgpu_demo=disabled -Dsubset=disabled \
        -Dtests=disabled -Dintrospection=disabled -Ddocs=disabled -Ddoc_tests=false -Dutilities=disabled \
        -Dbenchmark=disabled
    endgroup
}

build_libass() {
    group "libass"
    extract libass
    # Renomme la fonction interne read_file (pratique de BtbN : évite une collision de symbole en liaison statique).
    CFLAGS="$CFLAGS -Dread_file=libass_internal_read_file" \
    meson_static "$SRC/libass" "$BLD/libass" \
        -Dfontconfig=disabled -Ddirectwrite=enabled -Dcoretext=disabled -Dasm=enabled -Dlibunibreak=disabled \
        -Dtest=disabled -Dcompare=disabled -Dprofile=disabled -Dfuzz=disabled -Dcheckasm=disabled \
        -Drequire-system-font-provider=true -Dlarge-tiles=false \
        -Dc_args="-D_FORTIFY_SOURCE=2 -fstack-protector-strong -Dread_file=libass_internal_read_file"
    endgroup
}

build_shaderc() {
    group "shaderc (+ glslang, SPIRV-Tools, SPIRV-Headers)"
    extract shaderc
    extract glslang "$SRC/shaderc/third_party"
    extract spirv-tools "$SRC/shaderc/third_party"
    extract spirv-headers "$SRC/shaderc/third_party"
    cmake -S "$SRC/shaderc" -B "$BLD/shaderc" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TC" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
        -DENABLE_EXCEPTIONS=ON -DENABLE_GLSLANG_BINARIES=OFF -DENABLE_CTEST=OFF \
        -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_SKIP_TESTS=ON -DSPIRV_TOOLS_BUILD_STATIC=ON -DSPIRV_WERROR=OFF \
        -DBUILD_SHARED_LIBS=OFF
    # shaderc_combined : bibliothèque statique faite des objets de shaderc, glslang et SPIRV-Tools
    # (libshaderc/CMakeLists.txt, cmake/utils.cmake au commit épinglé) ; le .pc est écrit par la cible
    # « shaderc_combined-pkg-config », à la racine du répertoire de construction.
    ninja -C "$BLD/shaderc" -j"$JOBS" shaderc_combined shaderc_combined-pkg-config
    install -m 644 "$BLD/shaderc/libshaderc/libshaderc_combined.a" "$PREFIX/lib/"
    mkdir -p "$PREFIX/include/shaderc"
    install -m 644 "$SRC"/shaderc/libshaderc/include/shaderc/*.h "$PREFIX/include/shaderc/"
    local ver
    ver="$(sed -n 's/^Version: *//p' "$BLD/shaderc/shaderc_combined.pc" | head -1)"
    if [ -z "$ver" ]; then
        echo "version de shaderc introuvable (libplacebo exige shaderc >= 2019.1)" >&2
        exit 1
    fi
    cat > "$PREFIX/lib/pkgconfig/shaderc.pc" <<EOF
prefix=$PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: shaderc
Description: shaderc statique combiné (shaderc + glslang + SPIRV-Tools), construit par sme-media-build
Version: $ver
Libs: -L\${libdir} -lshaderc_combined -lstdc++
Cflags: -I\${includedir}
EOF
    endgroup
}

build_spirv_cross() {
    group "SPIRV-Cross"
    extract spirv-cross
    cmake -S "$SRC/spirv-cross" -B "$BLD/spirv-cross" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TC" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DSPIRV_CROSS_SHARED=OFF -DSPIRV_CROSS_STATIC=ON -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF \
        -DSPIRV_CROSS_FORCE_PIC=ON -DSPIRV_CROSS_ENABLE_CPP=OFF -DSPIRV_CROSS_ENABLE_MSL=OFF
    ninja -C "$BLD/spirv-cross" -j"$JOBS"
    ninja -C "$BLD/spirv-cross" install
    local maj min pch
    maj="$(sed -nE 's/.*set\(spirv-cross-abi-major ([0-9]+)\).*/\1/p' "$SRC/spirv-cross/CMakeLists.txt")"
    min="$(sed -nE 's/.*set\(spirv-cross-abi-minor ([0-9]+)\).*/\1/p' "$SRC/spirv-cross/CMakeLists.txt")"
    pch="$(sed -nE 's/.*set\(spirv-cross-abi-patch ([0-9]+)\).*/\1/p' "$SRC/spirv-cross/CMakeLists.txt")"
    if [ -z "$maj" ] || [ -z "$min" ] || [ -z "$pch" ]; then
        echo "version ABI de SPIRV-Cross introuvable (libplacebo exige >= 0.29.0)" >&2
        exit 1
    fi
    # mpv et libplacebo cherchent « spirv-cross-c-shared » : on le fait pointer sur les bibliothèques statiques.
    cat > "$PREFIX/lib/pkgconfig/spirv-cross-c-shared.pc" <<EOF
prefix=$PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include/spirv_cross

Name: spirv-cross-c-shared
Description: API C de SPIRV-Cross, liée statiquement (sme-media-build)
Version: $maj.$min.$pch
Libs: -L\${libdir} -lspirv-cross-c -lspirv-cross-glsl -lspirv-cross-hlsl -lspirv-cross-reflect -lspirv-cross-util -lspirv-cross-core -lstdc++
Cflags: -I\${includedir}
EOF
    endgroup
}

build_libplacebo() {
    group "libplacebo"
    extract libplacebo
    local sm
    for sm in $LIBPLACEBO_SUBMODULES; do
        extract "libplacebo-$(basename "$sm" | tr 'A-Z_' 'a-z-')"
    done
    meson_static "$SRC/libplacebo" "$BLD/libplacebo" -Dauto_features=disabled \
        -Dvulkan=disabled -Dvk-proc-addr=disabled -Dopengl=disabled -Dgl-proc-addr=disabled \
        -Dd3d11=enabled -Dglslang=disabled -Dshaderc=enabled \
        -Dlcms=disabled -Ddovi=disabled -Dlibdovi=disabled -Dunwind=disabled -Dxxhash=disabled \
        -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false -Ddebug-abort=false
    endgroup
}

build_luajit() {
    group "LuaJIT"
    extract luajit
    cd "$SRC/luajit"
    sed -i '/^Libs\.private/d' etc/luajit.pc
    # Mêmes réglages que ci/build-mingw64-full.sh de mpv (LUA52COMPAT, statique, amalgame).
    # src/Makefile ne définit pas LDFLAGS : sans « LDFLAGS= », celui de l'environnement (options de l'éditeur de
    # liens mingw) irait aussi aux outils de l'hôte (l. 192 et 204) ; il passe par TARGET_LDFLAGS (l. 232), cible seule.
    make TARGET_SYS=Windows PREFIX="$PREFIX" HOST_CC=gcc CFLAGS="-O2 -pipe" LDFLAGS= CROSS="$T-" \
        TARGET_CFLAGS="$CFLAGS" TARGET_LDFLAGS="$LDFLAGS" BUILDMODE=static XCFLAGS=-DLUAJIT_ENABLE_LUA52COMPAT \
        FILE_T=luajit.exe INSTALL_DEP=src/luajit.exe amalg install
    endgroup
}

build_mpv() {
    group "mpv (libmpv)"
    extract mpv
    # Sans .git, meson retombe sur MPV_VERSION (« 0.41.0-UNKNOWN ») : on y écrit la forme que produit
    # le CI de mpv sur un clone superficiel, pour que mpv-version nomme le commit (seule retouche de source).
    printf '0.41.0-dev-g%s\n' "${MPV_COMMIT:0:9}" > "$SRC/mpv/MPV_VERSION"
    local largs="'-static-libgcc', '-static-libstdc++', '-fstack-protector-strong', '-Wl,--no-insert-timestamp', '-Wl,-Map=$OUT/maps/libmpv-2.dll.map'"
    meson setup "$BLD/mpv" "$SRC/mpv" --cross-file "$CROSS" --prefix="$PREFIX" --libdir=lib \
        --buildtype=release --default-library=shared --prefer-static --wrap-mode=nofallback \
        -Dauto_features=disabled \
        -Dgpl=false -Dcplayer=false -Dlibmpv=true -Dtests=false -Dfuzzers=false -Dbuild-date=false \
        -Dlua=luajit \
        -Djavascript=disabled -Dlibcurl=disabled -Dlibbluray=disabled -Ddvdnav=disabled -Dlibarchive=disabled \
        -Dsubrandr=disabled -Dvapoursynth=disabled -Dopenal=disabled \
        -Dgl=disabled \
        -Dd3d11=enabled -Dshaderc=enabled -Dspirv-cross=enabled -Dd3d-hwaccel=enabled -Dd3d9-hwaccel=enabled \
        -Dwasapi=enabled -Dwin32-threads=enabled -Dzlib=enabled -Dvector=enabled \
        -Dc_link_args="[$largs]" -Dcpp_link_args="[$largs]" \
        | tee "$OUT/logs/mpv-meson-setup.txt"
    meson compile -C "$BLD/mpv"
    meson install -C "$BLD/mpv"
    meson introspect --buildoptions "$BLD/mpv" > "$OUT/meta/mpv-buildoptions.json"
    cp "$BLD/mpv/meson-logs/meson-log.txt" "$OUT/logs/mpv-meson-log.txt"
    endgroup
}

collect() {
    group "collecte"
    local f n
    for f in "$PREFIX"/bin/{avcodec,avdevice,avfilter,avformat,avutil,swresample,swscale}-*.dll "$PREFIX"/bin/libmpv-2.dll; do
        n="$(basename "$f")"
        cp "$f" "$OUT/unstripped/$n"
        "$T-strip" --strip-unneeded -o "$OUT/bin/$n" "$f"
    done
    "$T-strip" --strip-unneeded -o "$OUT/probe/ffprobe.exe" "$PREFIX/bin/ffprobe.exe"
    # dév. FFmpeg (compilation de PyAV) : en-têtes, .def (import MSVC régénéré par lib.exe), .dll.a, pkg-config,
    # et les DLL livrées (épurées), pour que le wheel embarque exactement les fichiers de bin/.
    mkdir -p "$OUT/dev/ffmpeg/include" "$OUT/dev/ffmpeg/bin"
    cp -r "$PREFIX"/include/lib{avcodec,avdevice,avfilter,avformat,avutil,swresample,swscale} "$OUT/dev/ffmpeg/include/"
    for f in "$PREFIX"/lib/{avcodec,avdevice,avfilter,avformat,avutil,swresample,swscale}-*.def \
             "$PREFIX"/lib/lib{avcodec,avdevice,avfilter,avformat,avutil,swresample,swscale}.dll.a \
             "$PREFIX"/bin/{avcodec,avdevice,avfilter,avformat,avutil,swresample,swscale}.lib; do
        cp "$f" "$OUT/dev/ffmpeg/lib/"
    done
    cp "$PREFIX"/lib/pkgconfig/lib{avcodec,avdevice,avfilter,avformat,avutil,swresample,swscale}.pc "$OUT/dev/ffmpeg/lib/pkgconfig/"
    cp "$OUT"/bin/{avcodec,avdevice,avfilter,avformat,avutil,swresample,swscale}-*.dll "$OUT/dev/ffmpeg/bin/"
    ls -l "$OUT/dev/ffmpeg/lib"
    local ndef nlib ndlla
    ndef="$(find "$OUT/dev/ffmpeg/lib" -maxdepth 1 -name '*.def' | wc -l)"
    nlib="$(find "$OUT/dev/ffmpeg/lib" -maxdepth 1 -name '*.lib' | wc -l)"
    ndlla="$(find "$OUT/dev/ffmpeg/lib" -maxdepth 1 -name '*.dll.a' | wc -l)"
    if [ "$ndef" != 7 ] || [ "$nlib" != 7 ] || [ "$ndlla" != 7 ]; then
        echo "dév. FFmpeg incomplet : $ndef .def, $nlib .lib, $ndlla .dll.a (7 attendus chacun)" >&2
        find "$PREFIX" \( -name '*.def' -o -name '*.lib' -o -name '*.dll.a' \) >&2
        exit 1
    fi
    # dév. libmpv
    mkdir -p "$OUT/dev/libmpv/include"
    cp -r "$PREFIX/include/mpv" "$OUT/dev/libmpv/include/"
    cp "$PREFIX"/lib/libmpv.dll.a "$OUT/dev/libmpv/lib/"
    cp "$SRC/mpv/LICENSE.LGPL" "$OUT/dev/libmpv/"
    cp "$SRC/ffmpeg-${FFMPEG_COMMIT:0:7}/COPYING.LGPLv2.1" "$SRC/ffmpeg-${FFMPEG_COMMIT:0:7}/LICENSE.md" "$OUT/dev/ffmpeg/"
    # tables d'import relevées par objdump (M3) ; audit.py les relit par son propre analyseur PE
    for f in "$OUT"/bin/*.dll "$OUT"/probe/*.exe; do
        echo "== $(basename "$f")"
        "$T-objdump" -p "$f" | grep -E '^[[:space:]]*DLL Name:' || true
    done > "$OUT/meta/objdump-imports.txt"
    cat "$OUT/meta/objdump-imports.txt"
    # empreintes
    (cd "$OUT" && sha256sum bin/* probe/* unstripped/* > meta/SHA256SUMS)
    ls -l "$OUT/bin" "$OUT/unstripped" "$OUT/probe" "$OUT/maps"
    cat "$OUT/meta/SHA256SUMS"
    endgroup
}

record_toolchain
build_zlib
build_dav1d
build_ffnvcodec
build_ffmpeg
build_freetype
build_fribidi
build_harfbuzz
build_libass
build_shaderc
build_spirv_cross
build_libplacebo
build_luajit
build_mpv
collect

group "balayage DA-7 (sortie de construction)"
python3 /recipe/recipe/audit.py scan --maps "$OUT/maps" --report "$OUT/meta/scan-build.json" \
    "$OUT/bin" "$OUT/unstripped" "$OUT/probe"
python3 /recipe/recipe/audit.py inventory --maps "$OUT/maps" --pins /recipe/pins.env \
    --json "$OUT/meta/inventory.json" --md "$OUT/meta/inventory.md"
endgroup
