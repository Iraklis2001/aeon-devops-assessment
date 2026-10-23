#!/usr/bin/env bash
# Updates the *dev* overlay with the immutable image tag from this build.
# Production is never mutated here. Promote with ci/promote-to-prod.sh.
set -euo pipefail

IMAGE_REPOSITORY="${IMAGE_REPOSITORY:?IMAGE_REPOSITORY is required}"
IMAGE_TAG="${IMAGE_TAG:?IMAGE_TAG is required}"
GITOPS_DEV_OVERLAY="${GITOPS_DEV_OVERLAY:-gitops/overlays/dev}"
BRANCH="gitops/dev-${IMAGE_TAG}"

git config user.name "${GIT_USERNAME:-aeon-ci-bot}"
git config user.email "ci-bot@example.invalid"

git checkout -B "${BRANCH}"

(
  cd "${GITOPS_DEV_OVERLAY}"
  kustomize edit set image "aeon/api=${IMAGE_REPOSITORY}:${IMAGE_TAG}"
)

git add "${GITOPS_DEV_OVERLAY}"
if git diff --cached --quiet; then
  echo "Dev overlay already points at ${IMAGE_REPOSITORY}:${IMAGE_TAG}"
  exit 0
fi

git commit -m "gitops(dev): deploy api@${IMAGE_TAG}"

# PLACEHOLDER: authenticate with GIT_TOKEN from Jenkins credentials, never from git.
# git push origin "${BRANCH}"
# gh pr create --base main --head "${BRANCH}" \
#   --title "gitops(dev): api@${IMAGE_TAG}" \
#   --body "Automated CI update. Image was tested and scanned in Jenkins."

echo "Prepared GitOps update for ${IMAGE_REPOSITORY}:${IMAGE_TAG} on ${BRANCH}"
echo "Push and open a PR against main so Argo CD can sync the merged overlay."
