# Example Voting App

A small distributed voting app and DevOps capstone. The Python vote service sends votes through Redis, a .NET worker stores them in PostgreSQL, and the Node.js result service streams totals to browsers.

## Run Locally

Install Docker with Compose v2, then create a local environment file and start the services:

```shell
cp .env.example .env
# Replace POSTGRES_PASSWORD with a unique local password.
docker compose up --build
```

Open [http://localhost:8080](http://localhost:8080) to vote and [http://localhost:8081](http://localhost:8081) to see results. The `.env` file is ignored by Git. To stop the app, press Ctrl+C and run `docker compose down`; add `--volumes` only when you also want to delete local vote data.

## Architecture

![Architecture diagram](architecture.excalidraw.png)

The Kubernetes deployment runs the same three application services with internal Redis and PostgreSQL services. PostgreSQL uses an encrypted EBS volume; the vote and result services are ClusterIP-only and can be reached with `kubectl port-forward`.

## CI/CD

`.github/workflows/ci-cd.yaml` runs the Docker Compose integration test, validates Terraform and Helm, and builds and scans each app image. Pushes publish images to Docker Hub under `DOCKER_USERNAME/example-voting-app-{vote,result,worker}`, tagged with the full commit SHA. When a pull request is merged to `main`, `.github/workflows/provision-infrastructure.yaml` applies Terraform and then deploys that merge commit to EKS with Helm, waiting for its images to be published first.

The first successful deployment requires these repository settings:

| Setting | Kind | Purpose |
| --- | --- | --- |
| `AWS_ACCESS_KEY_ID` | Actions secret | Access key ID for a dedicated IAM user used by the workflows |
| `AWS_SECRET_ACCESS_KEY` | Actions secret | Secret access key for that IAM user |
| `AWS_REGION` | Actions variable | Region for EKS and Terraform state |
| `AWS_IAM_PRINCIPAL_ARN` | Actions variable | ARN of the IAM user whose access keys are configured above |
| `DOCKER_USERNAME` | Actions secret | Docker Hub account that owns the application image repositories |
| `DOCKER_PASSWORD` | Actions secret | Docker Hub access token used to publish and pull images |
| `POSTGRES_PASSWORD` | Actions secret | Database password supplied to Kubernetes as a Secret |

Create a dedicated IAM user for GitHub Actions and store its access key ID and secret access key as repository secrets. Grant that user the permissions needed to create and secure the Terraform state bucket, read and write its state and lock files, and manage the EKS/IAM resources in `terraform/`, including `iam:PassRole` for the cluster and node roles. The bucket name is derived from the AWS account ID and region, so no bucket-name Actions variable is needed. Terraform grants this user EKS cluster-admin access so GitHub Actions can deploy Helm releases. Static access keys are long-lived credentials; restrict the user permissions, rotate the keys, and never commit them to the repository.

Set `AWS_IAM_PRINCIPAL_ARN` to the IAM user's ARN and `AWS_REGION` to the deployment region. Do not commit access keys, the database password, or the Docker Hub access token to the repository. Restrict `cluster_endpoint_public_access_cidrs` in `terraform/variables.tf` to your approved egress ranges when possible; EKS still requires IAM authentication for API access.

Merge a pull request into `main` to create the EKS cluster. The apply workflow uses Terraform to create and configure the account- and region-specific S3 state bucket before initializing the main state backend. The deployment workflow waits for the cluster to become active, writes the Kubernetes Secrets from Actions secrets, and installs/upgrades the `voting-app` Helm release. The Docker Hub repositories must be owned by `DOCKER_USERNAME` and accessible to the configured access token.

## Deploy And Roll Back

After deployment, run each command in a separate terminal to forward the internal services to your workstation:

```shell
kubectl port-forward -n voting-app svc/voting-app-example-voting-app-vote 8080:80
kubectl port-forward -n voting-app svc/voting-app-example-voting-app-result 8081:80
```

To demonstrate a bad release and recover it, use a deliberately unavailable image tag, then roll back to the previous Helm revision:

```shell
helm upgrade voting-app ./helm/example-voting-app -n voting-app --set-string images.tag=bad-release
helm history voting-app -n voting-app
helm rollback voting-app -n voting-app
kubectl rollout status -n voting-app deployment/voting-app-example-voting-app-vote
```

The failed release is recorded by Helm; `helm rollback` restores the last successful release. PostgreSQL data remains on its EBS volume while the cluster exists. Destroying the cluster deletes the volume and its data.

## Infrastructure Lifecycle

The Terraform root in `terraform/` creates an EKS cluster and managed node group in the account's default VPC. Before initializing that root, the workflow uses the separate `terraform/state/` configuration to create the private, encrypted, versioned S3 bucket used for Terraform state. Its name is derived from the AWS account ID and region. The bucket is protected from Terraform destruction and is retained when the EKS infrastructure is destroyed.

- A pull request merged into `main` runs the infrastructure apply workflow.
- Select **Destroy infrastructure** under Actions and check `confirm_destroy` to destroy the cluster. The Terraform state bucket is retained.
- Recreate the environment by merging a pull request after destruction.

EKS, EC2 nodes, and EBS storage incur AWS charges while provisioned. Destroy the environment when it is not in use.

## Existing Examples

`docker-compose.images.yml`, `docker-stack.yml`, and `k8s-specifications/` preserve the repository's original upstream sample images and their public demo credential (`postgres`). They are for disposable local demonstrations only; do not expose them or reuse that credential. The source-built Compose app and automated Helm deployment use externally supplied credentials. External workflow and registry data flows are listed in [`data-flows.yaml`](data-flows.yaml).

The voting application accepts one vote per client browser and updates that browser's existing vote rather than adding a second one.
