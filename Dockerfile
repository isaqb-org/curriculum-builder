# Base image pinned to an explicit version + multi-arch manifest digest.
# Renovate's Docker manager keeps both the tag and the digest current.
FROM ruby:4.0.6-alpine3.23@sha256:4d337707818921564ac698572b92b3ca178960bcd7f6c876e589d46afc057843 AS builder
ENV GEM_HOME=/opt/gems
ENV PATH=$GEM_HOME/bin:$PATH

# Themes track main; the REF is the pinned commit Renovate bumps on each new
# main commit (git-refs custom manager). Override with --build-arg.
ARG PDF_THEME_REPO=https://github.com/isaqb-org/pdf-theme
# renovate: currentValue=main
ARG PDF_THEME_REF=ccf2db3f350e3f254d9807bd80b8611617221f0b
ARG HTML_THEME_REPO=https://github.com/isaqb-org/html-theme
# renovate: currentValue=main
ARG HTML_THEME_REF=c93cd7debbe4c9116a379394229105ef5a65f0b7

RUN apk add --no-cache build-base git \
 && gem install --no-document asciidoctor:2.0.26 asciidoctor-pdf:2.3.27 \
 && for d in "pdf-theme:$PDF_THEME_REPO:$PDF_THEME_REF" "html-theme:$HTML_THEME_REPO:$HTML_THEME_REF"; do \
      name="${d%%:*}"; rest="${d#*:}"; repo="${rest%:*}"; ref="${rest##*:}"; \
      git init "/opt/isaqb/$name" \
   && git -C "/opt/isaqb/$name" fetch --depth 1 "$repo" "$ref" \
   && git -C "/opt/isaqb/$name" checkout --detach FETCH_HEAD; \
    done \
 && rm -rf /opt/isaqb/pdf-theme/.git /opt/isaqb/html-theme/.git

FROM ruby:4.0.6-alpine3.23@sha256:4d337707818921564ac698572b92b3ca178960bcd7f6c876e589d46afc057843
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
