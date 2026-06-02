FROM ruby:3.4-alpine AS builder
ENV GEM_HOME=/opt/gems
ENV PATH=$GEM_HOME/bin:$PATH

# Themes track main; picked up on the next image rebuild. Override with --build-arg.
ARG PDF_THEME_REPO=https://github.com/isaqb-org/pdf-theme
ARG PDF_THEME_REF=main
ARG HTML_THEME_REPO=https://github.com/isaqb-org/html-theme
ARG HTML_THEME_REF=main

RUN apk add --no-cache build-base git \
 && gem install --no-document asciidoctor:2.0.26 asciidoctor-pdf:2.3.24 \
 && git clone --depth 1 --branch "$PDF_THEME_REF"  "$PDF_THEME_REPO"  /opt/isaqb/pdf-theme \
 && git clone --depth 1 --branch "$HTML_THEME_REF" "$HTML_THEME_REPO" /opt/isaqb/html-theme \
 && rm -rf /opt/isaqb/pdf-theme/.git /opt/isaqb/html-theme/.git

FROM ruby:3.4-alpine
ENV GEM_HOME=/opt/gems
ENV PATH=$GEM_HOME/bin:$PATH

COPY --from=builder /opt/gems            /opt/gems
COPY --from=builder /opt/isaqb/pdf-theme /opt/isaqb/pdf-theme
COPY --from=builder /opt/isaqb/html-theme /opt/isaqb/html-theme
COPY extensions/   /opt/isaqb/extensions/
COPY build.sh      /opt/isaqb/build.sh
COPY build.config  /opt/isaqb/build.config.default

WORKDIR /project
ENTRYPOINT ["sh", "/opt/isaqb/build.sh"]
CMD []
