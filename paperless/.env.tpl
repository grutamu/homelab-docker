###############################################################################
# Paperless-ngx settings                                                      #
###############################################################################
COMPOSE_PROJECT_NAME=paperless
# See http://docs.paperless-ngx.com/configuration/ for all available options.

# The UID and GID of the user used to run paperless in the container. Set this
# to your UID and GID on the host so that you have write access to the
# consumption directory.
USERMAP_UID=1000
USERMAP_GID=1000

# See the documentation linked above for all options. A few commonly adjusted settings
# are provided below.

# This is required if you will be exposing Paperless-ngx on a public domain
# (if doing so please consider security measures such as reverse proxy)
PAPERLESS_URL=op://docker/paperless/PAPERLESS_URL

# Adjust this key if you plan to make paperless available publicly. It should
# be a very long sequence of random characters. You don't need to remember it.
PAPERLESS_SECRET_KEY=op://docker/paperless/PAPERLESS_SECRET_KEY

# Use this variable to set a timezone for the Paperless Docker containers. Defaults to UTC.
PAPERLESS_TIME_ZONE=America/Chicago

# The default language to use for OCR. Set this to the language most of your
# documents are written in.
PAPERLESS_OCR_LANGUAGE=eng

PAPERLESS_CONSUMER_POLLING=10
