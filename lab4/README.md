# Lab 4 - Containerise and Pipeline

Work done as non-root user `acs730-user`; the container runs as `appuser` (uid 10001).

## Build and run
    docker build -t acs730-lab4:slim lab4/
    docker run -d -p 8000:8000 acs730-lab4:slim
    curl http://localhost:8000/healthz    # {"status":"ok","version":"dev"}

## Image size
| Image | Base | Size | Rebuild after 1-line change |
|---|---|---|---|
| naive | python:latest (1.13 GB) | 1.15 GB | <your-number> s |
| slim | python:3.12-slim-bookworm (124 MB) | 130 MB | 0.6 s |

- **Base image:** about 1.0 GB of the gap is the base layer (1.13 GB vs 124 MB). The full Debian base ships compilers and libraries the app never uses.
- **Cache:** slim shows `CACHED` for pip install on a code-only rebuild because requirements.txt is copied before app.py. Naive runs `COPY . .` first, so every code edit reinstalls everything.
- **.dockerignore:** keeps .git, .github, __pycache__, .pytest_cache, evidence/, *.png, *.md and Dockerfiles out of the build context.

## CI timings
| Step | Baseline | Cache miss | Cache hit | Worth it? |
|---|---|---|---|---|
| pip install (test 3.12) | 2 s | 4 s | 2 s | No |
| docker build | 6 s | 23 s | 9 s | No |
| Whole workflow | 49 s | 77 s | 64 s | - |

Runs: baseline 39718939478, miss 39719262687 ("pip cache is not found"), hit 39719987660 ("Cache restored from key").

- **pip cache:** not worth it. Two small packages install in 2-4 s, about the same as restoring the cache.
- **Docker layer cache:** not worth it. A plain build took 6 s; buildx plus the GHA cache adds overhead, so even a hit (9 s) is slower. It pays off only when dependencies take minutes to build.

## Why tag by SHA, not latest
A `sha-` tag points to one commit forever, so you know exactly what code is running and rollback means deploying the previous SHA. `latest` moves on every push.

## Composite action vs reusable workflow
Dependency setup is a few steps that must run on the same runner as the tests, so it is a composite action. The image build is a whole job that needs `packages: write`, which the test job must not have, so it is a reusable workflow.

## GitHub Actions vs AWS-native
AWS-native would be CodePipeline (job graph), CodeBuild (runners) and ECR (registry). CodeBuild runs inside AWS with an IAM role; GitHub runners need only the built-in GITHUB_TOKEN. Academy denies IAM writes, so CodeBuild/CodePipeline roles cannot be created here. Recommendation: GitHub Actions, because the code already lives on GitHub and it needs no AWS credential. AWS-native suits an all-in-AWS team that wants IAM roles and CloudTrail auditing.

## Experiments
### 1. Invert the layer order
Prediction: a code edit will reinstall dependencies. Result: rebuild took 6.3 s and pip install ran again, vs 0.6 s normally. Why: Docker rebuilds every layer after the first changed one, so copying app.py first invalidates the dependency layer.

### 2. Delete the .dockerignore
Prediction: context grows, image does not. Result: image stayed 130 MB and `/app` held only app.py and requirements.txt. Why: my Dockerfile copies only those two files; the naive `COPY . .` would copy everything.
