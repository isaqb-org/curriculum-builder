#!/bin/sh
# In-image build. Renders the format x language x suffix matrix.
#   build.sh                 # all languages x formats
#   build.sh pdf DE          # single format + language
#   build.sh pdf DE REMARKS  # + suffix tag
# Config precedence: environment > repo build.config > baked default.
set -eu

REPO_ROOT=${REPO_ROOT:-/project}
ISAQB_HOME=${ISAQB_HOME:-/opt/isaqb}
EXT_DIR=${EXT_DIR:-$ISAQB_HOME/extensions}

[ -f "$REPO_ROOT/build.config" ]          && . "$REPO_ROOT/build.config"
[ -f "$ISAQB_HOME/build.config.default" ] && . "$ISAQB_HOME/build.config.default"

: "${CURRICULUM_FILE:?not set — set it in build.config or pass -e CURRICULUM_FILE=<docs/ AsciiDoc root, no .adoc>}"
LANGUAGES=${LANGUAGES:-"DE EN"}
SUFFIX_TAGS=${SUFFIX_TAGS:-""}
PREPRESS=${PREPRESS:-false}
VERSION=${RELEASE_VERSION:-LocalBuild}
VERSION_DATE=$(date +%Y%m%d)

DOCS="$REPO_ROOT/docs"
OUT="$REPO_ROOT/build"

PDF_THEME_DIR=${PDF_THEME_DIR:-$ISAQB_HOME/pdf-theme/themes}
PDF_FONTS_DIR=${PDF_FONTS_DIR:-$ISAQB_HOME/pdf-theme/fonts}
HTML_CSS=${HTML_CSS:-$ISAQB_HOME/html-theme/adoc-github.css}

PAGE_NUMBERING_RB="$EXT_DIR/robust-page-numbering.rb"
LG_OVERVIEW_RB="$EXT_DIR/learning-goals-overview.rb"

mkdir -p "$OUT"

common_attrs() {
  lang=$1; suffix=$2
  file_version="${VERSION}-${lang}"
  printf '%s' \
    "-a icons=font \
     -a version-label= \
     -a revnumber=${file_version} \
     -a revdate=${VERSION_DATE} \
     -a document-version=${file_version}-${VERSION_DATE} \
     -a currentDate=${VERSION_DATE} \
     -a release-version=${VERSION} \
     -a language=${lang} \
     -a curriculumFileName=${CURRICULUM_FILE} \
     -a data-uri \
     -a allow-uri-read \
     -a include-configuration=tags=**;${lang};!* \
     -a suffix=${suffix}"
}

render() {
  format=$1; lang=$2; suffix=$3
  suffix_part=""
  [ -n "$suffix" ] && suffix_part="-$(echo "$suffix" | tr '[:upper:]' '[:lower:]')"
  lang_lc=$(echo "$lang" | tr '[:upper:]' '[:lower:]')

  # shellcheck disable=SC2046
  if [ "$format" = "pdf" ]; then
    set -- $(common_attrs "$lang" "$suffix") \
      -a compress \
      -a pdf-themesdir="$PDF_THEME_DIR" -a pdf-theme=isaqb \
      -a pdf-fontsdir="$PDF_FONTS_DIR"
    [ "$PREPRESS" = "true" ] && set -- "$@" -a prepress
    asciidoctor-pdf -r "$PAGE_NUMBERING_RB" -r "$LG_OVERVIEW_RB" \
      --base-dir "$DOCS" -D "$OUT" "$@" "$DOCS/${CURRICULUM_FILE}.adoc"
    mv "$OUT/${CURRICULUM_FILE}.pdf" "$OUT/${CURRICULUM_FILE}${suffix_part}-${lang_lc}.pdf"
  else
    set -- $(common_attrs "$lang" "$suffix") \
      -a stylesheet="$HTML_CSS"
    asciidoctor -r "$LG_OVERVIEW_RB" \
      --base-dir "$DOCS" -D "$OUT" "$@" \
      "$DOCS/index.adoc" "$DOCS/${CURRICULUM_FILE}.adoc"
    mv "$OUT/${CURRICULUM_FILE}.html" "$OUT/${CURRICULUM_FILE}${suffix_part}-${lang_lc}.html"
  fi
  echo "  -> build/${CURRICULUM_FILE}${suffix_part}-${lang_lc}.${format}"
}

if [ "$#" -ge 2 ]; then
  render "$1" "$2" "${3:-}"
  exit 0
fi

for fmt in pdf html; do
  for lang in $LANGUAGES; do
    if [ -z "$SUFFIX_TAGS" ]; then
      echo "[$fmt $lang]"; render "$fmt" "$lang" ""
    else
      for sfx in $SUFFIX_TAGS; do
        echo "[$fmt $lang $sfx]"; render "$fmt" "$lang" "$sfx"
      done
    fi
  done
done
