# ffmpeg-allowlist.sh — liste d'autorisation de FFmpeg (DA-2), sourcée par build-all.sh.
# Méthode : --disable-everything --disable-autodetect, puis chaque composant nommé ici, avec sa raison.
# Point de départ : R-doc § 3.3 point 3 (demuxers, décodeurs vidéo/audio/sous-titres), augmenté des
# parseurs, filtres de bitstream, hwaccels et filtres que mpv et PyAV exigent. Aucun encodeur, aucun muxer.
# Les dépendances internes (bsf imposés par un décodeur, h263 pour mpeg4…) sont ajoutées par configure (_select).

FF_PROTOCOLS=(
    file              # PyAV ouvre les médias par chemin (avformat_open_input) ; mpv lit par son propre flux
)

FF_DEMUXERS=(
    mov               # MP4 / MOV / M4A : conteneur le plus fréquent des livraisons
    matroska          # MKV / WebM
    mxf               # MXF : XDCAM HD422, AVC-Intra, IMX/D10
    mpegts            # TS de diffusion
    mpegps            # MPEG-PS / VOB
    mpegvideo         # MPEG-1/2 élémentaire (.m2v)
    avi               # AVI
    asf               # WMV / WMA
    flv               # FLV
    gxf               # GXF (serveurs de diffusion)
    dv                # DV brut (.dv)
    wav               # WAV / BWF
    w64               # Sony Wave64
    aiff              # AIFF
    caf               # Apple CAF
    flac              # FLAC élémentaire
    mp3               # MP3 élémentaire
    aac               # AAC ADTS élémentaire
    ac3               # AC-3 élémentaire
    eac3              # E-AC-3 élémentaire
    dts               # DTS élémentaire
    dtshd             # DTS-HD élémentaire
    truehd            # Dolby TrueHD élémentaire
    s337m             # Dolby E encapsulé SMPTE 337M dans du PCM
    ogg               # Ogg (Vorbis, Opus)
    h264              # H.264 élémentaire
    hevc              # HEVC élémentaire
    m4v               # MPEG-4 Part 2 élémentaire
    vc1               # VC-1 élémentaire
    ivf               # IVF (VP8/VP9/AV1)
    obu               # AV1 en OBU
    srt               # SubRip
    ass               # ASS/SSA
    webvtt            # WebVTT
    scc               # Scenarist (EIA-608)
    mcc               # MacCaption (EIA-608/708)
)

FF_DECODERS=(
    # vidéo
    h264              # AVC, XAVC, AVC-Intra
    hevc              # HEVC
    mpeg1video        # MPEG-1
    mpeg2video        # MPEG-2, XDCAM, IMX/D10
    mpeg4             # MPEG-4 Part 2
    prores            # Apple ProRes
    dnxhd             # Avid DNxHD / DNxHR
    dvvideo           # DV, DVCPRO
    mjpeg             # Motion JPEG
    mjpegb            # Motion JPEG B (MOV)
    jpeg2000          # JPEG 2000 (MXF)
    cfhd              # GoPro CineForm (MOV de post-production)
    qtrle             # QuickTime Animation
    vc1               # VC-1
    wmv3              # WMV9
    msmpeg4v3         # MS-MPEG-4 v3 (DivX 3, « DIV3 ») en AVI : un échantillon AVI de M5 est refusé sans lui
    wmv1              # WMV 7 (ASF) : un échantillon WMV de M5 est refusé sans lui
    wmv2              # WMV 8 (ASF) : un échantillon WMV de M5 est refusé sans lui
    indeo5            # Intel Indeo Video 5 (IV50) en AVI : un échantillon AVI de M5 est refusé sans lui
    av1               # AV1 natif : support des hwaccels AV1 (d3d11va, dxva2, nvdec)
    libdav1d          # AV1 logiciel (dav1d)
    vp8               # VP8
    vp9               # VP9
    rawvideo          # vidéo non compressée
    v210              # 10 bits 4:2:2 non compressé
    v210x             # idem, variante
    v410              # 10 bits 4:4:4 non compressé
    r210              # 10 bits RVB non compressé
    r10k              # 10 bits RVB non compressé (AJA)
    ffv1              # FFV1 (archive)
    png               # PNG dans MOV/MKV
    # audio
    aac               # AAC
    aac_latm          # AAC LATM (TS)
    ac3               # AC-3
    eac3              # E-AC-3
    mp2               # MPEG-1/2 Layer II (TS de diffusion)
    mp2float          # idem, variante flottante
    mp3               # MP3
    mp3float          # idem, variante flottante
    pcm_s16le         # PCM 16 bits LE
    pcm_s16be         # PCM 16 bits BE (MOV)
    pcm_s24le         # PCM 24 bits LE (MXF, WAV)
    pcm_s24be         # PCM 24 bits BE (MOV)
    pcm_s32le         # PCM 32 bits LE
    pcm_s32be         # PCM 32 bits BE
    pcm_f32le         # PCM flottant LE
    pcm_f32be         # PCM flottant BE
    pcm_f64le         # PCM double LE
    pcm_s8            # PCM 8 bits signé
    pcm_u8            # PCM 8 bits non signé
    pcm_alaw          # A-law
    pcm_mulaw         # mu-law
    pcm_bluray        # PCM Blu-ray (M2TS)
    pcm_dvd           # PCM DVD (VOB)
    s302m             # SMPTE 302M (AES3 dans TS de diffusion)
    dolby_e           # Dolby E
    flac              # FLAC
    opus              # Opus
    vorbis            # Vorbis
    alac              # Apple Lossless
    dca               # DTS
    truehd            # Dolby TrueHD
    mlp               # MLP
    wmav2             # WMA 2 (ASF)
    # sous-titres
    ass               # ASS
    ssa               # SSA
    subrip            # SubRip
    srt               # SubRip (ancien identifiant)
    webvtt            # WebVTT
    movtext           # 3GPP Timed Text (MP4)
    dvbsub            # DVB bitmap
    dvdsub            # DVD bitmap
    pgssub            # Blu-ray PGS
    ccaption          # EIA-608 (sous-titres codés)
)

FF_PARSERS=(
    aac aac_latm ac3 dca flac mlp opus vorbis mpegaudio dolby_e   # flux audio des conteneurs élémentaires et TS/PS
    h264 hevc mpegvideo mpeg4video vc1 vp8 vp9 av1                # découpage des flux vidéo (TS, PS, élémentaires)
    mjpeg jpeg2000 dnxhd prores png                               # flux intra (MOV, MXF, AVI)
    dvbsub dvdsub                                                 # sous-titres bitmap en TS/PS
)

FF_BSFS=(
    # aucun en propre : ceux qu'exigent les décodeurs (vp9_superframe_split, etc.) sont tirés par configure
)

FF_HWACCELS=(
    h264_d3d11va h264_d3d11va2 h264_dxva2 h264_nvdec      # hwdec=auto-safe : d3d11va puis *-copy (vd_lavc.c l. 272-290)
    hevc_d3d11va hevc_d3d11va2 hevc_dxva2 hevc_nvdec
    mpeg2_d3d11va mpeg2_d3d11va2 mpeg2_dxva2 mpeg2_nvdec
    vc1_d3d11va vc1_d3d11va2 vc1_dxva2 vc1_nvdec
    wmv3_d3d11va wmv3_d3d11va2 wmv3_dxva2 wmv3_nvdec
    vp9_d3d11va vp9_d3d11va2 vp9_dxva2 vp9_nvdec
    av1_d3d11va av1_d3d11va2 av1_dxva2 av1_nvdec
)

FF_FILTERS=(
    # buffer, buffersink, abuffer, abuffersink : toujours compilés (allfilters.c l. 628-635), non listables
    format aformat                          # négociation de format (PyAV : AudioResampler = abuffer → aformat → abuffersink)
    scale aresample                         # conversions insérées automatiquement par libavfilter
    null anull                              # graphes passants
    hwupload hwdownload                     # transferts GPU ↔ mémoire dans un graphe lavfi
    bwdif                                   # désentrelaceur logiciel de mpv (f_auto_filters.c l. 159), hors liste GPL de LICENSE.md
)
