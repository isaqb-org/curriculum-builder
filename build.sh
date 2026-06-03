#!/bin/sh
# In-image build. Renders the format x language x suffix matrix.
#   build.sh                 # all languages x formats
#   build.sh pdf DE          # single format + language
#   build.sh pdf DE REMARKS  # + suffix tag
#   build.sh clean           # remove build/ outputs
# Config precedence: environment > repo build.config > baked default.
set -eu

REPO_ROOT=${REPO_ROOT:-/project}
ISAQB_HOME=${ISAQB_HOME:-/opt/isaqb}
EXT_DIR=${EXT_DIR:-$ISAQB_HOME/extensions}

[ -f "$REPO_ROOT/build.config" ]          && . "$REPO_ROOT/build.config"
[ -f "$ISAQB_HOME/build.config.default" ] && . "$ISAQB_HOME/build.config.default"

# Remove build outputs. No config required.
#   build.sh clean
if [ "${1:-}" = "clean" ]; then
  rm -rf "$REPO_ROOT/build"
  echo "cleaned build/"
  exit 0
fi

: "${CURRICULUM_FILE:?not set — set it in build.config or pass -e CURRICULUM_FILE=<docs/ AsciiDoc root, no .adoc>}"
LANGUAGES=${LANGUAGES:-"DE EN"}
SUFFIX_TAGS=${SUFFIX_TAGS:-""}
PREPRESS=${PREPRESS:-false}
VALID_FROM=${VALID_FROM:-""}
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

# Localized " (valid from ...)" suffix from VALID_FROM (YYYY/MM/DD). Empty if
# unset or malformed. Has spaces, so it is NOT emitted via common_attrs (which
# is word-split) but appended as a single quoted -a arg in render().
format_validity() {
  vf_lang=$1
  [ -z "$VALID_FROM" ] && return 0
  case "$VALID_FROM" in
    [0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]) ;;
    *) return 0 ;;
  esac
  vf_year=${VALID_FROM%%/*}
  vf_rest=${VALID_FROM#*/}
  vf_mnum=${vf_rest%%/*}; vf_mnum=${vf_mnum#0}
  vf_day=${vf_rest#*/};   vf_day=${vf_day#0}
  { [ "$vf_mnum" -ge 1 ] && [ "$vf_mnum" -le 12 ]; } 2>/dev/null || return 0
  if [ "$vf_lang" = "DE" ]; then
    set -- Januar Februar März April Mai Juni Juli August September Oktober November Dezember
    eval vf_mname=\${$vf_mnum}
    printf '%s' " (Gültig ab ${vf_day}. ${vf_mname} ${vf_year})"
  else
    set -- January February March April May June July August September October November December
    eval vf_mname=\${$vf_mnum}
    printf '%s' " (valid from ${vf_mname} ${vf_day}, ${vf_year})"
  fi
}

common_attrs() {
  lang=$1; suffix=$2
  file_version="${VERSION}-${lang}"
  printf '%s' \
    "-a icons=font \
     -a version-label= \
     -a revnumber=${file_version} \
     -a revdate=${VERSION_DATE} \
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

  docver="${VERSION}-${lang}-${VERSION_DATE}$(format_validity "$lang")"

  # shellcheck disable=SC2046
  if [ "$format" = "pdf" ]; then
    set -- $(common_attrs "$lang" "$suffix") \
      -a compress \
      -a pdf-themesdir="$PDF_THEME_DIR" -a pdf-theme=isaqb \
      -a pdf-fontsdir="$PDF_FONTS_DIR" \
      -a "document-version=$docver"
    [ "$PREPRESS" = "true" ] && set -- "$@" -a prepress
    asciidoctor-pdf -r "$PAGE_NUMBERING_RB" -r "$LG_OVERVIEW_RB" \
      --base-dir "$DOCS" -D "$OUT" "$@" "$DOCS/${CURRICULUM_FILE}.adoc"
    mv "$OUT/${CURRICULUM_FILE}.pdf" "$OUT/${CURRICULUM_FILE}${suffix_part}-${lang_lc}.pdf"
  else
    set -- $(common_attrs "$lang" "$suffix") \
      -a stylesheet="$HTML_CSS" \
      -a "document-version=$docver"
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
