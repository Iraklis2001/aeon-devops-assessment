# AEON `api` delivery assessment

Take-home CI/CD, Kubernetes, and GitOps design for a small HTTP service. The goal is a coherent, secure path from commit to cluster — not a full production platform.

**Time spent:** about 3.5 focused hours.

**AI assistance:** an AI coding assistant helped draft files. I reviewed every stage, credential boundary, and promotion gate and can explain the trade-offs below.

## Local validation

```bash
python -m venv .venv
# Windows: .venv\Scripts\activate
source .venv/bin/activate
pip install -r requirements-dev.txt
pytest -q

docker build -t aeon-api:test .
docker run --rm -p 8080:8080 aeon-api:test
# curl http://127.0.0.1:8080/healthz

kustomize build gitops/overlays/dev
kustomize build gitops/overlays/prod
```

If `kustomize` is not installed, `kubectl kustomize gitops/overlays/dev` is equivalent. These commands do not need AWS. Jenkins, ECR, and Argo CD stages are specified so a reviewer can see behaviour; they are marked `PLACEHOLDER` where a real account would be required.

## Assumptions

- One repository holds the app and GitOps manifests so the assessment is easy to review. In production I would split them so deploy history cannot be bypassed by an application commit.
- Registry `111111111111.dkr.ecr.eu-west-1.amazonaws.com/aeon/api` is a placeholder ECR repo.
- Jenkins has a Linux agent, Trivy, a Kubernetes cloud agent for Kaniko/crane, and credential `gitops-bot`.
- `dev` and `prod` are separate namespaces here (and separate EKS clusters in AWS). Argo CD Applications already encode that split.
- The application is a stand-in HTTP service. Delivery workflow is the focus.

## Image build safety

Jenkins builds with **Kaniko** in an unprivileged Kubernetes pod using a dedicated `jenkins-kaniko` ServiceAccount (IRSA to ECR). Kaniko does not need a Docker daemon, so it avoids Docker-in-Docker’s privileged socket.

The image is written to a tarball, **scanned with Trivy** (`HIGH`/`CRITICAL`, fail the build), then **pushed with crane** only on `main`. GitOps is updated only after that push. Credentials are Jenkins credentials or IRSA — nothing is committed.

BuildKit on a locked-down remote builder is a reasonable alternative. DinD is faster to demo and worse for security because the daemon socket is a breakout path.

## Promotion flow

1. A change lands on `main`.
2. Jenkins runs unit tests, builds an immutable image tagged with the 12-character Git SHA, and scans it.
3. The image is pushed to ECR as `repo:<sha>` (never `latest`).
4. `ci/update-gitops.sh` sets that tag on **dev only** and opens a PR.
5. Argo CD auto-syncs `gitops/overlays/dev`.
6. After soak, `ci/promote-to-prod.sh` copies the **same tag** into the prod overlay and opens a second PR. Prod cannot receive an untested image because CI never writes the prod overlay.

Jenkins does not run `kubectl apply`. Argo CD is the only reconciler.

**Rollback:** revert (or set the previous SHA in) the prod overlay and merge. Argo CD self-heal deploys the last known-good image. `kubectl rollout undo` is an emergency brake; Git must be updated afterwards so GitOps does not re-apply the bad revision.

## Secrets on AWS

No secret values are in Git. The Deployment references `secretKeyRef` `api-secrets` as optional so local `kustomize build` still works. The intended AWS pattern is Secrets Manager + External Secrets Operator with IRSA (`gitops/examples/external-secret.yaml`). SOPS-encrypted files in Git are an alternative if ESO is not available. Jenkins uses credential IDs, not `.env` files.

## What I skipped (time limit)

Terraform/Terragrunt for VPC, EKS, RDS, and state; a live Jenkins/EKS; image digest pinning in addition to SHA tags; NetworkPolicies, HPA, PDB; canary/analysis; a real Trivy run against ECR.

## Next production improvements

Pin images by digest; separate app and GitOps repos; admission policy (Kyverno/OPA) to block `:latest` and privileged pods; central logs/metrics/traces; backup and restore of Terraform state and cluster add-ons; signed images (Cosign) and admission verification.

## Follow-up: intermittent 502s after a release

Argo CD “healthy” only means the desired ReplicaSet is ready. I would check the ingress/ALB 5xx rate, compare error rate to the deploy timestamp, inspect pod restarts and `kubectl logs`/`describe` for crash loops or readiness flaps, confirm the Service endpoints match ready pods, and look at upstream timeouts (RDS, timeouts, thread exhaustion). If 5xx is rising and tied to the new SHA, roll back via Git immediately, then keep the bad revision for a post-incident: resource limits, probe timing, connection pool, or a bad dependency. If only some pods fail, it may be a rollout/readiness issue rather than the image itself.

Word count of design notes is intentionally in the 500–700 range requested.
