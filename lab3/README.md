# Lab 3 - Terraform Remote State and CI/CD Pipeline

## Credential Model: OIDC vs Session Credentials
In a production AWS environment, GitHub Actions uses OpenID Connect (OIDC) to assume an IAM role directly using short-lived tokens without storing static secrets or access keys. In AWS Academy, the `iam:CreateOpenIDConnectProvider` API action is denied by permission boundaries, so session-scoped credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) are refreshed via script; if leaked, their potential damage is strictly limited by the expiration timer of the temporary Vocareum lab session.
