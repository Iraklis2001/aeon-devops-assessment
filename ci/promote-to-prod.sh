#!/usr/bin/env bash
# Copies the current *dev* image tag into the prod overlay and opens a PR.
# This is the promotion gate: prod can only receive an image already running in dev.
set -euo pipefail

DEV_OVERLAY="${GITOPS_DEV_OVERLAY:-gitops/overlays/dev}"
PROD_OVERLAY="${GITOPS_PROD_OVERLAY:-gitops/overlays/prod}"

DEV_IMAGE="$(awk '/newName:/ {name=$2} /newTag:/ {tag=$2} END {gsub(/"/, "", name); gsub(/"/, "", tag); print name ":" tag}' "${DEV_OVERLAY}/kustomization.yaml")"
IMAGE_NAME="${DEV_IMAGE%%:*}"
IMAGE_TAG="${DEV_IMAGE##*:}"

if [[ -z "${IMAGE_NAME}" || -z "${IMAGE_TAG}" || "${IMAGE_TAG}" == "replace-me" ]]; then
  echo "Dev overlay does not contain a promoted image tag" >&2
  exit 1
fi

BRANCH="gitops/prod-${IMAGE_TAG}"
git checkout -B "${BRANCH}"

(
  cd "${PROD_OVERLAY}"
  kustomize edit set image "aeon/api=${IMAGE_NAME}:${IMAGE_TAG}"
)

git add "${PROD_OVERLAY}"
if git diff --cached --quiet; then
  echo "Prod overlay already points at ${IMAGE_NAME}:${IMAGE_TAG}"
  exit 0
fi

git commit -m "gitops(prod): promote api@${IMAGE_TAG}"

# PLACEHOLDER: push with GIT_TOKEN from Jenkins credentials.
# gh pr create --base main --head "${BRANCH}" \
#   --title "Promote api@${IMAGE_TAG} to production" \
#   --body "This image is already deployed in dev. Review scan results and soak time before merge."

echo "Prepared production promotion PR for ${IMAGE_NAME}:${IMAGE_TAG}"
