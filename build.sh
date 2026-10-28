#!/bin/bash
#
# Build, tag, and publish the whisper-cuda-12 image.
#
# The whisper.cpp version in the Dockerfile (WHISPER_VERSION / WHISPER_COMMIT)
# is the single source of truth for both the Docker tags and the git tag:
#
#   Docker:  <image>:v1.9.5
#            <image>:v1.9.5-d1be6fd   (version + upstream commit)
#            <image>:latest
#   git:     v1.9.5 (annotated, pointing at the commit that was built)
#
# The git tag is only created after the image builds and is pushed, so a broken
# build never gets tagged.
#
# Environment overrides:
#   IMAGE=joedefen/whisper-cuda-12   image repository
#   DOCKERFILE=Dockerfile            Dockerfile to read the version from
#   WHISPER_VERSION / WHISPER_COMMIT override the Dockerfile values
#   TAG_NAME=v1.9.5                  git tag name (default: WHISPER_VERSION)
#   PUSH=0                           skip `docker push`
#   GIT_TAG=0                        skip creating the git tag
#   GIT_PUSH=0                       create the git tag but do not push it
#   FORCE_TAG=1                      move an existing git tag to HEAD
#   ALLOW_DIRTY=1                    allow tagging while the tree is dirty
#
# Examples:
#   ./build.sh                       build, push images, create+push git tag
#   PUSH=0 GIT_TAG=0 ./build.sh      build locally only (for testing)
#   PUSH=0 GIT_PUSH=0 ./build.sh     build, then tag locally for review
set -euo pipefail

cd "$(dirname "$0")"

IMAGE="${IMAGE:-joedefen/whisper-cuda-12}"
DOCKERFILE="${DOCKERFILE:-Dockerfile}"
PUSH="${PUSH:-1}"
GIT_TAG="${GIT_TAG:-1}"
GIT_PUSH="${GIT_PUSH:-1}"
FORCE_TAG="${FORCE_TAG:-0}"
ALLOW_DIRTY="${ALLOW_DIRTY:-0}"

# Print the default value of `ARG NAME=value` from the Dockerfile.
dockerfile_arg() {
    awk -v key="$1" '
        $1 == "ARG" && index($2, key "=") == 1 {
            print substr($2, length(key) + 2)
            exit
        }
    ' "$DOCKERFILE"
}

WHISPER_VERSION="${WHISPER_VERSION:-$(dockerfile_arg WHISPER_VERSION)}"
WHISPER_COMMIT="${WHISPER_COMMIT:-$(dockerfile_arg WHISPER_COMMIT)}"

if [ -z "$WHISPER_VERSION" ] || [ -z "$WHISPER_COMMIT" ]; then
    echo "ERROR: could not read WHISPER_VERSION/WHISPER_COMMIT from $DOCKERFILE" >&2
    exit 1
fi

SHORT_COMMIT="$(printf '%s' "$WHISPER_COMMIT" | cut -c1-7)"
TAG_NAME="${TAG_NAME:-$WHISPER_VERSION}"
SOURCE_REVISION="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

echo "==> whisper.cpp: $WHISPER_VERSION ($WHISPER_COMMIT)"
echo "==> images:      $IMAGE:$WHISPER_VERSION"
echo "                 $IMAGE:$WHISPER_VERSION-$SHORT_COMMIT"
echo "                 $IMAGE:latest"
echo "==> git tag:     $TAG_NAME"

# --- Preflight -------------------------------------------------------------
# Validate git tagging before spending time on a build, so a conflict cannot
# leave us with pushed images but no tag.
if [ "$GIT_TAG" = "1" ]; then
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "ERROR: GIT_TAG=1 but this is not a git repository (set GIT_TAG=0)" >&2
        exit 1
    fi
    if [ -n "$(git status --porcelain)" ] && [ "$ALLOW_DIRTY" != "1" ]; then
        echo "ERROR: working tree is dirty; commit the source the tag should point at" >&2
        echo "       (or set ALLOW_DIRTY=1 to tag HEAD anyway, or GIT_TAG=0)" >&2
        exit 1
    fi
    if git rev-parse -q --verify "refs/tags/$TAG_NAME" >/dev/null; then
        tagged_commit="$(git rev-list -n 1 "$TAG_NAME")"
        head_commit="$(git rev-parse HEAD)"
        if [ "$tagged_commit" = "$head_commit" ]; then
            echo "==> git tag $TAG_NAME already points at HEAD; not re-creating it"
            GIT_TAG=0
        elif [ "$FORCE_TAG" = "1" ]; then
            echo "==> FORCE_TAG=1: will move git tag $TAG_NAME to HEAD"
        else
            echo "ERROR: git tag $TAG_NAME already exists at ${tagged_commit:0:7}, not HEAD" >&2
            echo "       Bump WHISPER_VERSION, or pick another TAG_NAME" >&2
            echo "       (e.g. TAG_NAME=$TAG_NAME-2), or set FORCE_TAG=1 to move it." >&2
            exit 1
        fi
    fi
fi

# --- Build -----------------------------------------------------------------
docker build \
    --build-arg WHISPER_VERSION="$WHISPER_VERSION" \
    --build-arg WHISPER_COMMIT="$WHISPER_COMMIT" \
    --build-arg SOURCE_REVISION="$SOURCE_REVISION" \
    -t "$IMAGE:$WHISPER_VERSION" \
    -t "$IMAGE:$WHISPER_VERSION-$SHORT_COMMIT" \
    -t "$IMAGE:latest" \
    .

# --- Push image ------------------------------------------------------------
if [ "$PUSH" = "1" ]; then
    docker push "$IMAGE:$WHISPER_VERSION"
    docker push "$IMAGE:$WHISPER_VERSION-$SHORT_COMMIT"
    docker push "$IMAGE:latest"
else
    echo "==> PUSH=0: skipping docker push"
fi

# --- Git tag ---------------------------------------------------------------
if [ "$GIT_TAG" = "1" ]; then
    if git rev-parse -q --verify "refs/tags/$TAG_NAME" >/dev/null; then
        # Only reachable with FORCE_TAG=1; move the tag to the built commit.
        git tag -f -a "$TAG_NAME" -m "whisper.cpp $WHISPER_VERSION ($WHISPER_COMMIT)"
    else
        git tag -a "$TAG_NAME" -m "whisper.cpp $WHISPER_VERSION ($WHISPER_COMMIT)"
    fi
    echo "==> created git tag $TAG_NAME"

    if [ "$GIT_PUSH" = "1" ]; then
        if [ "$FORCE_TAG" = "1" ]; then
            git push --force origin "$TAG_NAME"
        else
            git push origin "$TAG_NAME"
        fi
    else
        echo "==> GIT_PUSH=0: git tag $TAG_NAME exists locally only"
    fi
else
    echo "==> GIT_TAG=0: skipping git tag"
fi
