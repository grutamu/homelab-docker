# yaml-language-server: $schema=https://schemas.recyclarr.dev/v8/config-schema.json
################################################################################
## TRaSH-Guides v8 template format.
## API keys are injected from 1Password at deploy time (op inject); the
## resolved recyclarr.yml is gitignored. See deploy.sh.
################################################################################

sonarr:
  web-1080p-v4:
    base_url: http://sonarr:8989
    api_key: op://docker/recyclarr/SONARR_API_KEY

    quality_definition:
      type: series

    quality_profiles:
      - trash_id: 72dae194fc92bf828f32cde7744e51a1  # WEB-1080p
        reset_unmatched_scores:
          enabled: true

    custom_format_groups:
      add:
        - trash_id: 158188097a58d7687dee647e04af0da3  # [Optional] Golden Rule HD
          select:
            - 47435ece6b99a0b477caf360e79ba0bb  # x265 (HD)
            # - 9b64dff695c2115facf1b6ea59c9bd07  # x265 (no HDR/DV)
        - trash_id: 85fae4a2294965b75710ef2989c850eb  # [Streaming Services] HD/UHD boost
        - trash_id: 59c3af66780d08332fdc64e68297098f  # [Unwanted] Unwanted Formats
          select:
            - 15a05bc7c1a36e2b57fd628f8977e2fc  # AV1
            - 32b367365729d530ca1c124a0b180c64  # Bad Dual Groups
            - 85c61753df5da1fb2aab6f2a47426b09  # BR-DISK
            - 6f808933a71bd9666531610cb8c059cc  # BR-DISK (BTN)
            - fbcb31d8dabd2a319072b84fc0b7249c  # Extras
            - 9c11cd3f07101cdba90a2d81cf0e56b4  # LQ
            - e2315f990da2e2cbfc9fa5b7a6fcfe48  # LQ (Release Title)
            - 23297a736ca77c0fc8e70f8edd7ee56c  # Upscaled

radarr:
  sqp-1-1080p:
    base_url: http://radarr:7878
    api_key: op://docker/recyclarr/RADARR_API_KEY

    quality_definition:
      type: sqp-streaming

    quality_profiles:
      - trash_id: 0896c29d74de619df168d23b98104b22  # [SQP] SQP-1 (1080p)
        reset_unmatched_scores:
          enabled: true

    custom_format_groups:
      add:
        - trash_id: 15b1cf0b6f1a1493856a4355907affee  # [Unwanted] Unwanted Formats SQP
          select:
            - b6832f586342ef70d9c128d40c07b872  # Bad Dual Groups
            - cc444569854e9de0b084ab2b8b1532b2  # Black and White Editions
            - e6886871085226c3da1830830146846c  # Generated Dynamic HDR
            - bfd8eb01832d646a0a89c4deb46f8564  # Upscaled
