logger:
  default: info

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
    device: GPU # not AUTO — see readme.md

model:
  width: 300
  height: 300
  input_tensor: nhwc
  input_pixel_format: bgr
  path: /openvino-model/ssdlite_mobilenet_v2.xml
  labelmap_path: /openvino-model/coco_91cl_bkgr.txt

detect:
  enabled: true # must be explicit — see readme.md

ffmpeg:
  hwaccel_args: preset-intel-qsv-h264

birdseye:
  enabled: false

snapshots:
  enabled: true

record:
  enabled: true
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

review:
  alerts:
    labels:
      - car
      - person

go2rtc:
  streams:
    frigate_front_hq: rtspx://192.168.1.1:7441/Iu7PTWnVramD4hyn
    frigate_front_lq: rtspx://192.168.1.1:7441/wJUTOiaAWvzFj0CX
    frigate_frontdoor_hq: rtspx://192.168.1.1:7441/aW5kuiYd6041kfpv
    frigate_frontdoor_lq: rtspx://192.168.1.1:7441/wGHaudajQAV9316J
    frigate_patio_hq: rtspx://192.168.1.1:7441/dmTPm1QgPIo8exM3
    frigate_patio_lq: rtspx://192.168.1.1:7441/9GU3KNq2hSW7qEuQ
    frigate_garage_hq: rtspx://192.168.1.1:7441/xnexsGcsDCI8PxZY
    frigate_garage_lq: rtspx://192.168.1.1:7441/aDWsDvkL16CmQpiB
    frigate_packagecam: rtspx://192.168.1.1:7441/mpgv0uUu622nxXTQ

cameras:
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

  frigate_patio:
    ffmpeg:
      inputs:
        - path: rtsp://localhost:8554/frigate_patio_lq
          input_args: preset-rtsp-restream
          roles:
            - detect
        - path: rtsp://localhost:8554/frigate_patio_hq
          input_args: preset-rtsp-restream
          roles:
            - record
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

version: 0.18-0 # must match the image tag — see readme.md
