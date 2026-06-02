# Base image pinned to an explicit version + multi-arch manifest digest.
# Renovate's Docker manager keeps both the tag and the digest current.
FROM ruby:4.0.5-alpine3.23@sha256:378d06a06edb7e90ed4deef6293129729203b232283c2ecf62f066e17fab10e6 AS builder
ENV GEM_HOME=/opt/gems
ENV PATH=$GEM_HOME/bin:$PATH

# Themes track main; the REF is the pinned commit Renovate bumps on each new
# main commit (git-refs custom manager). Override with --build-arg.
ARG PDF_THEME_REPO=https://github.com/isaqb-org/pdf-theme
# renovate: currentValue=main
ARG PDF_THEME_REF=d1ea13013d7de542c7297b1938183f85fc13353c
ARG HTML_THEME_REPO=https://github.com/isaqb-org/html-theme
# renovate: currentValue=main
ARG HTML_THEME_REF=7533fc8b4c357d15ccd791ecdf0f8fa56af33fd0

RUN apk add --no-cache build-base git \
 && gem install --no-document asciidoctor:2.0.26 asciidoctor-pdf:2.3.24 \
 && for d in "pdf-theme:$PDF_THEME_REPO:$PDF_THEME_REF" "html-theme:$HTML_THEME_REPO:$HTML_THEME_REF"; do \
      name="${d%%:*}"; rest="${d#*:}"; repo="${rest%:*}"; ref="${rest##*:}"; \
      git init "/opt/isaqb/$name" \
   && git -C "/opt/isaqb/$name" fetch --depth 1 "$repo" "$ref" \
   && git -C "/opt/isaqb/$name" checkout --detach FETCH_HEAD; \
    done \
 && rm -rf /opt/isaqb/pdf-theme/.git /opt/isaqb/html-theme/.git

FROM ruby:4.0.5-alpine3.23@sha256:378d06a06edb7e90ed4deef6293129729203b232283c2ecf62f066e17fab10e6
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
