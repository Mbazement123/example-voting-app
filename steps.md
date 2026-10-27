# Run Example Voting App on AWS

This guide deploys the application to Amazon EKS using the repository's GitHub Actions workflows. Terraform creates the EKS cluster and node group; GitHub Actions builds and publishes the application images to GHCR, then Helm deploys the application.

> **Cost and credentials:** EKS, EC2 worker nodes, EBS volumes, and related AWS resources incur charges. The workflows authenticate with long-lived IAM access keys because this repository is configured for access-key authentication. Use a dedicated IAM user, grant only the permissions it needs, rotate its keys, and store them only as GitHub Actions secrets. Never paste credentials into source files or commit them.

## 1. Prepare your tools and AWS account

You need:

- An AWS account with permission to create IAM, EKS, EC2, EBS, and S3 resources.
- A GitHub account with admin access to this repository's Actions secrets and variables.
- AWS CLI v2 for the local verification and `kubectl` steps below.
- `kubectl` compatible with the Kubernetes version in `terraform/variables.tf`.
- Helm 3 if you want to inspect or operate the Helm release locally.

Confirm the AWS CLI is installed:

```shell
aws --version
```

Configure a local profile for the AWS identity you will use to provision the state bucket and infrastructure. Do not use root credentials:

```shell
aws configure --profile aws-admin
aws sts get-caller-identity --profile aws-admin
```

The Terraform configuration uses the account's **default VPC** and its subnets. Confirm the selected region has a default VPC and enough available addresses/subnets for EKS:

```shell
aws ec2 describe-vpcs \
  --profile aws-admin \
  --region us-east-1 \
  --filters Name=isDefault,Values=true \
  --query 'Vpcs[].VpcId' \
  --output table
```

Change `us-east-1` below and in later commands if you deploy in another region. The same region must be used consistently for the Terraform backend and EKS cluster.

## 2. Terraform state bucket

The Terraform bootstrap configuration creates an S3 bucket named `example-voting-app-terraform-state-<AWS-account-ID>-<AWS-region>` before the main Terraform backend is initialized. The account ID and region make the name globally unique and deterministic. Terraform enables versioning and encryption, blocks public access, and enforces bucket-owner ownership. The bucket is retained when you destroy the EKS infrastructure.

The workflow uses S3 native state locking (`use_lockfile=true`). The AWS identity used by GitHub Actions needs permission to create and configure this bucket and to read and write the state objects and lock files.

## 3. Create and configure the GitHub Actions IAM user

Create a dedicated IAM user in AWS for the workflows and generate an access key for it. The user needs permissions to:

- Read the default VPC and subnets.
- Create, update, inspect, and delete the EKS cluster, managed node group, and EKS add-on.
- Create and manage the IAM roles and policy attachments declared in `terraform/main.tf`, pass the cluster and node roles to AWS services, and create the EKS service-linked role if AWS requires it.
- Create and configure the Terraform state bucket, and read and write its state objects and lock files.
- Describe the cluster and update kubeconfig for deployment.

Keep its policy limited to the required account, region, resources, and state bucket where practicable. Terraform grants this IAM user **EKS cluster-admin access** so the deploy workflow can install Helm resources. Protect the access key, rotate it, and deactivate/delete it when no longer needed.

Record the IAM user ARN. It has a form similar to:

```text
arn:aws:iam::123456789012:user/github-actions-example-voting-app
```

Do not use the example ARN; use the ARN for the IAM user you created.

## 4. Set GitHub repository secrets and variables

In the repository, open **Settings → Secrets and variables → Actions** and add:

### Repository secrets

| Name | Value |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | Access key ID for the dedicated IAM user |
| `AWS_SECRET_ACCESS_KEY` | Secret access key for that IAM user |
| `POSTGRES_PASSWORD` | A strong, unique database password |
| `GHCR_PULL_TOKEN` | GitHub token with `read:packages` access to the repository's GHCR packages |

### Repository variables

| Name | Value |
| --- | --- |
| `AWS_REGION` | AWS region for the cluster and state bucket, for example `us-east-1` |
| `AWS_IAM_PRINCIPAL_ARN` | ARN of the IAM user associated with the AWS access keys |
| `GHCR_USERNAME` | GitHub username that owns the `GHCR_PULL_TOKEN` |

Use the full IAM **user** ARN for `AWS_IAM_PRINCIPAL_ARN`, not an IAM role ARN. The access keys and ARN must belong to the same user.

For local `kubectl` access later, configure a profile using the same IAM user's access keys. Enter the key values at the prompts rather than putting them in shell commands:

```shell
aws configure --profile voting-app
aws sts get-caller-identity --profile voting-app
```

Verify that the returned ARN matches `AWS_IAM_PRINCIPAL_ARN`.

## 5. Provision the EKS infrastructure

The infrastructure workflow runs when a pull request targeting `main` is merged. It derives the S3 state bucket name from the AWS account ID and region, bootstraps the bucket with Terraform, then initializes the main Terraform configuration with that bucket and applies the EKS resources.

1. Push your project changes to a branch and open a pull request targeting `main`.
2. Wait for the **CI and deploy** workflow's tests, Terraform validation, Helm lint, image builds, and scans to complete successfully.
3. Merge the pull request.
4. Open **Actions → Provision infrastructure** and inspect the run. Wait for the Terraform apply job to finish successfully.

The cluster name created by the current Terraform configuration is `voting-app-dev`. Infrastructure creation may take several minutes. If the concurrent deploy job fails while waiting for the cluster, rerun the failed deploy job after provisioning succeeds.

### Provision locally with Terraform instead

Use this path instead of merging a pull request to run Terraform from your workstation. Install Terraform 1.10.0 or later, configure the `voting-app` AWS CLI profile as described above, and run these commands from the repository root. Replace the example values with your region, IAM user ARN, and public IPv4 CIDR. The bootstrap script derives the state bucket name from your AWS account and region. Limit the EKS API endpoint to your approved egress IP; the Terraform default currently allows `0.0.0.0/0`.

```shell
export AWS_PROFILE=voting-app
export AWS_REGION=us-east-1
export TF_STATE_BUCKET="example-voting-app-terraform-state-$(aws sts get-caller-identity --query Account --output text)-$AWS_REGION"
export AWS_IAM_PRINCIPAL_ARN=arn:aws:iam::123456789012:user/github-actions-example-voting-app
export EKS_API_CIDR=YOUR_PUBLIC_IPV4/32

bash terraform/bootstrap-state.sh

terraform -chdir=terraform init -input=false \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="key=example-voting-app/$AWS_REGION/terraform.tfstate" \
  -backend-config="region=$AWS_REGION" \
  -backend-config="encrypt=true" \
  -backend-config="use_lockfile=true"

terraform -chdir=terraform plan -input=false -out=tfplan \
  -var="aws_region=$AWS_REGION" \
  -var="github_actions_principal_arn=$AWS_IAM_PRINCIPAL_ARN" \
  -var="cluster_endpoint_public_access_cidrs=[\"$EKS_API_CIDR\"]"

terraform -chdir=terraform apply -input=false tfplan
```

Review the plan before applying it. Terraform creates AWS resources that incur charges. The bootstrap script creates and configures the bucket if it does not exist, and stores its own Terraform state in that bucket. Keep the same region and IAM principal values for later Terraform operations. Do not run both the local Terraform path and the GitHub Actions apply path against different state keys.

Check the cluster status:

```shell
aws eks describe-cluster \
  --profile voting-app \
  --name voting-app-dev \
  --region YOUR_AWS_REGION \
  --query 'cluster.status' \
  --output text
```

Expected output:

```text
ACTIVE
```

## 6. Deploy the application

On pushes to `main`, the **CI and deploy** workflow tests the application, validates Terraform and Helm, builds and scans the three service images, pushes them to GHCR tagged with the commit SHA, and then deploys that SHA with Helm.

The workflow also creates/updates these Kubernetes Secrets in the `voting-app` namespace:

- `voting-app-db` for the PostgreSQL password.
- `ghcr-pull` for pulling the GHCR images.

Open **Actions → CI and deploy** and wait for the **Deploy to EKS** job to finish. Confirm the workloads are ready:

```shell
aws eks update-kubeconfig \
  --profile voting-app \
  --region YOUR_AWS_REGION \
  --name voting-app-dev

kubectl get nodes
kubectl get pods,services,pvc -n voting-app
```

The pods should reach `Running`/`Ready`, and the PostgreSQL PVC should become `Bound`. The application services are internal `ClusterIP` services; they are not public load balancers.

### Deploy the Helm YAML chart manually

The file `helm/example-voting-app/templates/resources.yaml` is a Helm template, not a plain Kubernetes YAML file. Render and install it with Helm; do not run `kubectl apply -f` directly on the template. The following commands assume the cluster is provisioned, the `voting-app` AWS profile is configured, and the application images have already been pushed to GHCR. A push to `main` runs the image build and publishes images tagged with that commit's full SHA.

Configure local access and select the image tag from the successful **CI and deploy** run:

```shell
export AWS_PROFILE=voting-app
export AWS_REGION=us-east-1
export GITHUB_REPOSITORY=OWNER/REPOSITORY
export IMAGE_TAG=FULL_COMMIT_SHA

aws eks update-kubeconfig \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name voting-app-dev

kubectl get nodes
```

Create the namespace and database Secret. The password is read without echoing and sent through standard input rather than included in the command line:

```shell
kubectl create namespace voting-app --dry-run=client -o yaml | kubectl apply -f -

read -r -s -p "PostgreSQL password: " POSTGRES_PASSWORD
printf '\n'
printf '%s' "$POSTGRES_PASSWORD" |
  kubectl create secret generic voting-app-db \
    --namespace voting-app \
    --from-file=password=/dev/stdin \
    --dry-run=client -o yaml |
  kubectl apply -f -
unset POSTGRES_PASSWORD
```

Create the GHCR pull Secret using a temporary Docker config. Enter a GitHub token with `read:packages` access when prompted. The temporary config is removed when the shell exits:

```shell
export GHCR_USERNAME=YOUR_GITHUB_USERNAME
docker_config_dir="$(mktemp -d)"
trap 'rm -r -- "$docker_config_dir"' EXIT

read -r -s -p "GHCR read:packages token: " GHCR_PULL_TOKEN
printf '\n'
printf '%s' "$GHCR_PULL_TOKEN" |
  docker --config "$docker_config_dir" login ghcr.io \
    --username "$GHCR_USERNAME" \
    --password-stdin
unset GHCR_PULL_TOKEN

kubectl create secret generic ghcr-pull \
  --namespace voting-app \
  --type=kubernetes.io/dockerconfigjson \
  --from-file=.dockerconfigjson="$docker_config_dir/config.json" \
  --dry-run=client -o yaml |
  kubectl apply -f -
```

Install the chart. The image names match the repository's CI workflow (`ghcr.io/OWNER/REPOSITORY-vote`, `-result`, and `-worker`):

```shell
image_root="ghcr.io/$(printf '%s' "$GITHUB_REPOSITORY" | tr '[:upper:]' '[:lower:]')"

helm upgrade --install voting-app ./helm/example-voting-app \
  --namespace voting-app \
  --set-string "images.vote.repository=$image_root-vote" \
  --set-string "images.result.repository=$image_root-result" \
  --set-string "images.worker.repository=$image_root-worker" \
  --set-string "images.tag=$IMAGE_TAG" \
  --wait --timeout 10m

kubectl get pods,services,pvc -n voting-app
```

If the images are private, the `GHCR_USERNAME` and token must be authorized to pull them. The workflow path creates these same Kubernetes Secrets automatically; do not repeat the manual secret creation when the workflow has already created them.

## 7. Open the voting and results pages

The local AWS identity used by `kubectl` must be authorized for the cluster. Terraform adds the configured `AWS_IAM_PRINCIPAL_ARN` IAM user to EKS with cluster-admin access. The profile was configured in step 4. If using a different IAM user locally, add that user as an EKS access entry before expecting `kubectl` access.

```shell
kubectl get pods -n voting-app
```

Open two terminals and start one port-forward in each:

```shell
kubectl port-forward -n voting-app svc/voting-app-example-voting-app-vote 8080:80
```

```shell
kubectl port-forward -n voting-app svc/voting-app-example-voting-app-result 8081:80
```

Visit:

- Voting page: <http://localhost:8080>
- Results page: <http://localhost:8081>

Keep both port-forward commands running while using the pages. Press Ctrl+C in each terminal to stop forwarding.

## 8. Troubleshoot common problems

Inspect the resources and recent events:

```shell
kubectl get pods,services,pvc -n voting-app
kubectl get events -n voting-app --sort-by=.lastTimestamp
```

View logs for a pod:

```shell
kubectl logs -n voting-app deployment/voting-app-example-voting-app-vote
kubectl logs -n voting-app deployment/voting-app-example-voting-app-result
kubectl logs -n voting-app deployment/voting-app-example-voting-app-worker
```

Common causes:

- **AWS credentials or access denied:** Check the two AWS Actions secrets, their IAM user's policy, the region, and the `AWS_IAM_PRINCIPAL_ARN` variable.
- **Terraform state errors:** Confirm the region is correct and the IAM user can create/configure the account- and region-specific bucket and access its state and lock objects.
- **EKS access denied:** Confirm Terraform completed and the local AWS identity matches the IAM user ARN configured for EKS, or add a separate EKS access entry for your local identity.
- **Image pull errors / `ImagePullBackOff`:** Check that the GHCR packages exist and are accessible to `GHCR_USERNAME`/`GHCR_PULL_TOKEN`; the token needs `read:packages`.
- **Missing secret:** Confirm `POSTGRES_PASSWORD` and the GHCR credentials are set in Actions and the deployment workflow completed its secret-creation step.
- **PVC pending:** Confirm the EBS CSI add-on is active and the cluster's node group is healthy. EBS volumes are provisioned in the same availability zone as their node.
- **Pods not ready:** Inspect the pod events and logs above. Wait for PostgreSQL and Redis to become ready before investigating dependent service startup.
- **Deploy failed before EKS became active:** Wait until the provision workflow succeeds, then rerun the failed deploy job in its Actions run.

## 9. Roll back an application release

Review the Helm release history:

```shell
helm history voting-app -n voting-app
```

Roll back to the previous successful revision:

```shell
helm rollback voting-app -n voting-app
kubectl rollout status -n voting-app deployment/voting-app-example-voting-app-vote
```

## 10. Destroy the AWS infrastructure

Destroying the infrastructure removes the EKS cluster, node group, and the EBS volume containing PostgreSQL data. Back up anything you need first. The S3 Terraform state bucket is retained.

1. Open **Actions → Destroy infrastructure**.
2. Select **Run workflow** and set `confirm_destroy` to `true`.
3. Run the workflow and verify that the destroy job completes.

The workflow uses the same AWS secrets and variables as provisioning and ensures the protected state bucket exists before initializing the main Terraform configuration. Do not delete the state bucket until you are certain you no longer need the Terraform state.

If you provisioned locally with Terraform, destroy the infrastructure from the repository root using the same profile, region, IAM principal, and EKS API CIDR values used for apply. Set `TF_STATE_BUCKET` to the derived bucket name and run `bash terraform/bootstrap-state.sh` first so Terraform can initialize the bucket's bootstrap state:

```shell
terraform -chdir=terraform destroy -input=false \
  -var="aws_region=$AWS_REGION" \
  -var="github_actions_principal_arn=$AWS_IAM_PRINCIPAL_ARN" \
  -var="cluster_endpoint_public_access_cidrs=[\"$EKS_API_CIDR\"]"
```

The command prompts for confirmation. It destroys the cluster and its EBS-backed vote data; it does not delete the S3 state bucket.
