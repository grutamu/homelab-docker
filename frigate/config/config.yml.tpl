logger:
  default: info
  # logs:
  #   frigate.record: debug

mqtt:
  enabled: true
  host: op://docker/frigate/FRIGATE_MQTT_HOST
  topic_prefix: frigate
  user: op://docker/frigate/FRIGATE_MQTT_USER
  password: op://docker/frigate/FRIGATE_MQTT_PASSWORD

database:
  path: /config/frigate.db

detectors:
  ov:
    type: openvino
    # GPU, not AUTO. AUTO silently falls back to CPU if the OpenVINO GPU plugin
    # cannot initialise -- detection keeps working, just on the CPU, so the only
    # symptom is load. Pinning it makes a broken Level Zero / compute-runtime
    # stack fail loudly, which matters when moving the host to NixOS.
    device: GPU

model:
  width: 300
  height: 300
  input_tensor: nhwc
  input_pixel_format: bgr
  path: /openvino-model/ssdlite_mobilenet_v2.xml
  labelmap_path: /openvino-model/coco_91cl_bkgr.txt

# Must be set explicitly. DetectConfig.enabled defaults to False, and the only
# thing that ever turned it on was migrate_016_0(), which ran solely because the
# config declared an older version. Now that `version:` tracks the running
# release, no migration runs and the default applies — so this has to be stated.
detect:
  enabled: true

ffmpeg:
  hwaccel_args: preset-intel-qsv-h264

birdseye:
  enabled: false

snapshots:
  enabled: true
  # timestamp: true
  # bounding_box: true
  # crop: false
  # retain:
  #   default: 10

record:
  enabled: true
  # 0.17 split the old `retain: {days, mode}` into separate continuous/motion
  # retention, and dropped `mode` from each. The old `mode: all` kept 3 days of
  # both, so both are set to 3 here to preserve the previous behaviour exactly.
  continuous:
    days: 3
  motion:
    days: 3
  alerts:
    retain:
      days: 30
      mode: motion
  detections:
    retain:
      days: 30
      mode: motion
objects:
  track:
    - person
    - car
    # - dog
    # - cat
    # - motorcycle
    # - bus
    # - bird
    # - fox
    # - goat
    # - squirrel
    # - bicycle
    # - face
    # - package
    # - license_plate

review:
  alerts:
    labels:
      - car
      - person
      # - motorcycle
  # detections:
  #   labels:
  #     - cat
  #     - dog
  #     - bus
  #     - bird
  #     - fox
  #     - goat
  #     - squirrel
  #     - bicycle
  #     - face
  #     - package
  #     - license_plate

# motion:
#   enabled: true
#   # threshold: 70
#   # lightning_threshold: 0.8
#   # contour_area: 20
#   # frame_alpha: 0.01
#   # frame_height: 100
#   # # mask: 0.683,0.04,0.683,0.084,0.974,0.079,0.975,0.038
#   # improve_contrast: true
#   mqtt_off_delay: 30

go2rtc:
  streams:
    frigate_frontdoor_hq: rtspx://192.168.1.1:7441/aW5kuiYd6041kfpv
    frigate_frontdoor_lq: rtspx://192.168.1.1:7441/wGHaudajQAV9316J
    frigate_packagecam: rtspx://192.168.1.1:7441/mpgv0uUu622nxXTQ
    frigate_garage_hq: rtspx://192.168.1.1:7441/xnexsGcsDCI8PxZY
    frigate_garage_lq: rtspx://192.168.1.1:7441/aDWsDvkL16CmQpiB
    frigate_front_hq: rtspx://192.168.1.1:7441/Iu7PTWnVramD4hyn
    frigate_front_lq: rtspx://192.168.1.1:7441/wJUTOiaAWvzFj0CX

cameras:
  frigate_frontdoor:
    ffmpeg:
      inputs:
        - path: rtsp://localhost:8554/frigate_frontdoor_lq
          input_args: preset-rtsp-restream
          roles:
            - detect
        - path: rtsp://localhost:8554/frigate_frontdoor_hq
          input_args: preset-rtsp-restream
          roles:
            - record
      output_args:
        record: preset-record-ubiquiti

  frigate_packagecam:
    ffmpeg:
      inputs:
        - path: rtsp://localhost:8554/frigate_packagecam
          input_args: preset-rtsp-restream
          roles:
            - record
            - detect
      output_args:
        record: preset-record-ubiquiti

  frigate_garage:
    ffmpeg:
      inputs:
        - path: rtsp://localhost:8554/frigate_garage_lq
          input_args: preset-rtsp-restream
          roles:
            - detect
        - path: rtsp://localhost:8554/frigate_garage_hq
          input_args: preset-rtsp-restream
          roles:
            - record
      output_args:
        record: preset-record-ubiquiti

  frigate_front:
    ffmpeg:
      inputs:
        - path: rtsp://localhost:8554/frigate_front_lq
          input_args: preset-rtsp-restream
          roles:
            - detect
        - path: rtsp://localhost:8554/frigate_front_hq
          input_args: preset-rtsp-restream
          roles:
            - record
      output_args:
        record: preset-record-ubiquiti
    zones:
      driveway:
        coordinates: 0.136,0.285,0.433,0.163,0.671,0.354,0.977,0.659,0.86,1,0.221,0.997,0.161,0.676
        loitering_time: 0
# Must match CURRENT_CONFIG_VERSION in the running image. Kept current on
# purpose: Frigate only migrates a config it considers old, and it never writes
# the result back here because deploy.sh re-injects this template every run. A
# stale value means the whole migration chain replays on every single start, and
# the file on disk silently stops matching what actually runs.
version: 0.18-0