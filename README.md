# iSAQB curriculum builder (Ruby toolchain)

A self-contained, native-Ruby toolchain for rendering iSAQB Advanced Level curricula to PDF
and HTML. It replaces the JVM/Gradle (`asciidoctorj`) build with native MRI `asciidoctor` +
`asciidoctor-pdf` — significantly faster, and a single pinned Docker image instead of a JDK,
Gradle, and theme submodules in every curriculum repo.

The repo lives at `isaqb-org/curriculum-builder`. It produces a multi-arch Docker image
published to the GitHub Container Registry (GHCR); curriculum repos pull a pinned digest of
that image and need nothing else installed locally.

> **Migration status:** the legacy Gradle build remains authoritative. This image is being
> rolled out and validated first; the Gradle tooling will be retired step by step once the
> image is released and tested in real curriculum repos.

## What's in the image

- **`asciidoctor` + `asciidoctor-pdf`** — pinned to explicit versions in the `Dockerfile`;
  Renovate keeps them current. No source highlighter is bundled (the curriculum sets no
  `:source-highlighter:`).
- **`extensions/`** — the two render extensions, baked into `/opt/isaqb/extensions`:
  - `learning-goals-overview.rb` — builds the "Learning Goals Overview" section and tags the
    first chapter `arabic-start`. Ruby port of the legacy `SpecialTocTreeprocessor.groovy`,
    verified functionally equivalent.
  - `robust-page-numbering.rb` — roman front matter up to the first chapter, arabic after. It
    reads the `arabic-start` role set by the treeprocessor, so the two extensions must stay
    in sync.
- **`pdf-theme` and `html-theme`** — cloned from their `main` branch into `/opt/isaqb`, so
  curriculum repos no longer need the theme submodules.
- **`build.sh`** — the render matrix (format × language × suffix); the in-image `ENTRYPOINT`.
- **`build.config`** — baked as the default config; a curriculum's own `build.config` overrides it.

The image is built for both `linux/amd64` and `linux/arm64`, so it runs natively on Intel/AMD
hosts and on Apple Silicon / ARM CI alike.

## Using it from a curriculum repo

A curriculum repo consumes the published image directly: bind-mount the repo at `/project`,
pass the per-curriculum keys as environment, and let the image entrypoint render into `./build`.
Curriculum repos typically wrap this in a small build script of their own (which lives there,
not in this repo).

```bash
docker run --rm -u "$(id -u):$(id -g)" \
  -v "$PWD:/project" -w /project \
  -e CURRICULUM_FILE=curriculum-template -e LANGUAGES="DE EN" \
  ghcr.io/isaqb-org/curriculum-builder:2026              # all languages × pdf+html -> ./build
```

Positional arguments select a subset of the matrix:

```bash
# single format + language
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/project" -w /project \
  -e CURRICULUM_FILE=curriculum-template \
  ghcr.io/isaqb-org/curriculum-builder:2026 pdf DE

# + suffix tag
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/project" -w /project \
  -e CURRICULUM_FILE=curriculum-template \
  ghcr.io/isaqb-org/curriculum-builder:2026 pdf DE REMARKS
```

No JDK, Gradle, Ruby, or theme submodules required on the host.

### build.config

The few per-curriculum keys (the native equivalent of the old `build.gradle` `ext{}` block):

| Key               | Meaning                                                        | Default              |
|-------------------|----------------------------------------------------------------|----------------------|
| `CURRICULUM_FILE` | AsciiDoc root in `docs/` (no `.adoc`); also the output name     | **required** (build fails if unset) |
| `LANGUAGES`       | Space-separated languages to build                             | `DE EN`              |
| `SUFFIX_TAGS`     | Space-separated extra variants exposed as `{suffix}`           | (empty)              |
| `PREPRESS`        | PDF print/book layout (recto starts + binding margins)         | `false`              |

Precedence (highest first): `docker run -e` environment > repo `build.config` > baked default.
CI sets the version separately via `RELEASE_VERSION`.

### Pinning the image

Curriculum repos reference the image by tag plus an explicit digest:

```sh
IMAGE="ghcr.io/isaqb-org/curriculum-builder:2026"
DIGEST="sha256:<digest from the latest release>"
```

The tag is the release **major** (the year — see [Versioning](#versioning-and-publishing)).
Pin `DIGEST` to a published digest, found on the release page or in the workflow run summary;
the digest is what guarantees a reproducible, immutable image. A Renovate custom manager in the
**curriculum** repo keeps both current — match the `IMAGE`/`DIGEST` lines of that repo's build
script and set `"datasourceTemplate": "docker"`.

## Versioning and publishing

Releases use iSAQB **calendar versioning**: `v<year>.<minor>-rev<patch>`, e.g. `v2026.1-rev0`
(major `2026`, minor `1`, patch `rev0`). A release tag publishes these image tags:
`2026.1-rev0`, `2026.1`, `2026`, and `latest`. Downstream pins the major (`:2026`) plus a digest.

`.github/workflows/build-image.yml` runs on every pull request, on push to `main`, and on
`v*` tags (plus manual `workflow_dispatch`). The build/publish split is deliberate:

- **PR / `main` / dispatch** — builds the image for **both architectures** (the arm64 image is
  cross-built under QEMU) to validate that it compiles. Nothing is pushed.
- **`v*` tag** — builds, pushes the multi-arch manifest list to `ghcr.io/<owner>/<repo>`, and
  creates a matching **GitHub release**. The release notes and the run summary both carry the
  digest to pin downstream. Because the pushed digest is the manifest-list (index) digest, a
  single pinned digest resolves to the right CPU architecture automatically.

Renovate (`renovate.json`, extending the `isaqb-org/renovate-config` preset) keeps the pinned
base image and gems current. Merge a bump, cut a release tag, and a fresh digest is published.
Themes are not pinned — they track `main` and refresh on each rebuild.

## Local image build (development)

```bash
docker build -t ghcr.io/isaqb-org/curriculum-builder:dev .

# build for a specific platform:
docker build --platform linux/arm64 -t ghcr.io/isaqb-org/curriculum-builder:dev .

# override a theme ref or repo while developing:
docker build --build-arg PDF_THEME_REF=some-branch -t ghcr.io/isaqb-org/curriculum-builder:dev .
```

## Parity with the legacy Gradle build

`build.sh` reproduces the `build.gradle` attribute map and task matrix exactly (icons, version
labels, `include-configuration` tag filter, `data-uri`, compress, prepress, theme/font dirs,
HTML stylesheet), and the two extensions are ported verbatim in behaviour. PDF output has been
confirmed equivalent to the legacy build.

This checklist documents what the toolchain must reproduce — useful when validating a migration
step or investigating a rendering regression after a gem bump:

1. "Learning Goals Overview" / "Lernziele im Überblick" lists every `LG-*`/`LZ-*` goal, each
   linking to the right anchor.
2. Roman page numbers on copyright/TOC/overview, switching to arabic at the first chapter.
3. PDF outline/bookmarks and in-TOC page numbers match.
4. Fonts, theme colours, and embedded images render identically.
```

