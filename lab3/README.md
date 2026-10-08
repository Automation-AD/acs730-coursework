# Lab 3 - Terraform Remote State and CI/CD Pipeline

## Credential Model: OIDC vs Session Credentials
In a production AWS environment, GitHub Actions uses OpenID Connect (OIDC) to assume an IAM role directly using short-lived tokens without storing static secrets or access keys. In AWS Academy, the `iam:CreateOpenIDConnectProvider` API action is denied by permission boundaries, so session-scoped credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) are refreshed via script; if leaked, their potential damage is strictly limited by the expiration timer of the temporary Vocareum lab session.

## Operational Scenarios
* **ExpiredToken:** If a workflow fails with `ExpiredToken`, the AWS Academy lab session has ended. To fix this, start a new lab session in Vocareum and run `./scripts/refresh-gha-creds.sh <repo>` to push fresh credentials without changing repository code.
* **Input required and not supplied: aws-region:** This error occurs when the `AWS_REGION` variable is missing from GitHub repository variables (e.g. running workflows before the refresh script ran, or looking under secrets instead of vars). Running `./scripts/refresh-gha-creds.sh` sets this variable.
* **Terraform Version:** Terraform v1.10.3 was used across both the local workstation and GitHub Actions runners.

## Experiments

### Experiment 1: Expired Credentials
* **Prediction:** Rerunning the deploy workflow after a session ends will fail at the `Configure AWS session credentials` or `aws sts get-caller-identity` step with `ExpiredToken`.
* **Observation:** The workflow failed during STS authentication with an expired security token error.
* **Explanation:** Temporary session credentials issued by Vocareum are bounded by a fixed TTL; once expired, STS rejects the token signature until new credentials are generated and pushed via the refresh helper.

### Experiment 2: Remove the Remote Backend
* **Prediction:** Removing the S3 backend and migrating state locally causes GitHub Actions runners to lack knowledge of existing resources.
* **Observation:** Running `terraform init -migrate-state` creates a local `terraform.tfstate` file, and CI plan proposes recreating resources from scratch (`1 to add`).
* **Explanation:** Without a shared remote state backend in S3, each runner initializes with a clean, blank slate, leading to resource collisions or duplicate provisioning.
