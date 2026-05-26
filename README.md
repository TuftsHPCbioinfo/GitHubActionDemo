# Automating Container Builds with GitHub Actions: From Code to Docker Hub

> Demo repository for the TTS Summit 2026 talk (50 min)  
> **Presenter**: Yucheng Zhang, Tufts University  
> **Docker Hub image**: [`tuftsttsrt/rstudio`](https://hub.docker.com/r/tuftsttsrt/rstudio)

---

## Overview

This repository demonstrates how to use **GitHub Actions** to automatically build a Docker image and publish it to Docker Hub whenever a new GitHub Release is created. The image extends the popular [`rocker/tidyverse`](https://rocker-project.org/) base to provide a ready-to-use **RStudio Server** environment with pre-installed R packages.

### What You'll Learn

- How GitHub Actions workflows are triggered by repository events
- How to authenticate with Docker Hub using repository secrets
- How Docker image tags are automatically derived from release versions
- How build caching speeds up subsequent builds

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── docker_image.yml   # GitHub Actions workflow
├── Dockerfile                 # Docker image definition
└── README.md
```

---

## Dockerfile Explained

```dockerfile
FROM rocker/tidyverse:4.5.2
```

**Base image**: Starts from `rocker/tidyverse:4.5.2`, which bundles R 4.5.2, RStudio Server, and the core tidyverse packages (ggplot2, dplyr, tidyr, readr, etc.).

```dockerfile
ENV PATH="${PATH}:/usr/lib/rstudio-server/bin" \
    LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/lib/R/lib"
```

**Environment variables**: Ensures the RStudio Server binaries and R shared libraries are discoverable on the system PATH and linker path.

```dockerfile
RUN echo "session-timeout-minutes=0" >> /etc/rstudio/rsession.conf && \
    echo "session-save-action-default=no" >> /etc/rstudio/rsession.conf && \
    echo "copilot-enabled=1" >> /etc/rstudio/rsession.conf
```

**RStudio configuration**:

| Setting | Effect |
|---|---|
| `session-timeout-minutes=0` | Disables session timeout — sessions stay alive indefinitely (useful for long-running HPC jobs) |
| `session-save-action-default=no` | Prevents RStudio from prompting to save the workspace on exit (encourages reproducibility) |
| `copilot-enabled=1` | Enables GitHub Copilot integration in RStudio |

```dockerfile
RUN echo 'options(repos = c(CRAN = "https://cloud.r-project.org"))' \
    >> /usr/local/lib/R/etc/Rprofile.site
```

**CRAN mirror**: Sets the RStudio CRAN mirror globally so `install.packages()` works without prompting users to choose a mirror.

```dockerfile
RUN Rscript -e "install.packages(c('here', 'janitor'))"
```

**Pre-installed packages**: Installs two additional R packages into the image:

- **`here`** — simplifies file path management in R projects
- **`janitor`** — provides functions for cleaning and examining data

---

## GitHub Actions Workflow Explained

The workflow lives at `.github/workflows/docker_image.yml`.

### Trigger

```yaml
on:
  release:
    types: [published]
```

The workflow runs **only** when a new GitHub Release is published (e.g., tagging `v1.0.0` and clicking "Publish release"). It does **not** run on regular pushes or pull requests.

#### Other Common Trigger Options

GitHub Actions supports many [workflow triggers](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows). Here are the most useful ones for Docker builds:

**Push to a branch** — build on every commit to `main`:

```yaml
on:
  push:
    branches: [main]
```

**Pull request** — build (but don't push) on PRs to verify the image still builds:

```yaml
on:
  pull_request:
    branches: [main]
```

**Push a tag** — build when a version tag is pushed (without creating a full GitHub Release):

```yaml
on:
  push:
    tags:
      - 'v*'
```

**Scheduled (cron)** — rebuild on a schedule, e.g., weekly, to pick up base image security patches:

```yaml
on:
  schedule:
    - cron: '0 6 * * 1'   # Every Monday at 6:00 AM UTC
```

**Manual dispatch** — add a "Run workflow" button in the Actions tab for on-demand builds:

```yaml
on:
  workflow_dispatch:
```

**Path filter** — only trigger when specific files change (avoids rebuilds for README-only edits):

```yaml
on:
  push:
    branches: [main]
    paths:
      - 'Dockerfile'
      - '.github/workflows/docker_image.yml'
```

You can also **combine multiple triggers** in a single workflow:

```yaml
on:
  release:
    types: [published]
  workflow_dispatch:
  schedule:
    - cron: '0 6 * * 1'
```

> **Pro-Tip**: For production images, using `release` (as we do here) gives you explicit version control. Combine it with `workflow_dispatch` so you can re-trigger a build manually if needed, and `schedule` to pick up upstream security fixes automatically.

### Runner

```yaml
runs-on: ubuntu-24.04-arm
```

Uses a GitHub-hosted **ARM64** runner (Ubuntu 24.04). This matches the target platform (`linux/arm64`) and avoids the overhead of cross-architecture emulation.

### Steps Breakdown

#### 1. Checkout

```yaml
- name: Checkout
  uses: actions/checkout@v4
```

Clones the repository so the workflow has access to the `Dockerfile` and build context.

#### 2. Set up Docker Buildx

```yaml
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3
```

Installs [Docker Buildx](https://docs.docker.com/build/buildx/), an extended build tool that supports advanced features like build caching and multi-platform builds.

#### 3. Login to Docker Hub

```yaml
- name: Login to Docker Hub
  uses: docker/login-action@v3
  with:
    username: ${{ vars.DOCKERHUB_USERNAME }}
    password: ${{ secrets.DOCKERHUB_PASSWORD }}
```

Authenticates with Docker Hub using credentials stored in the repository:

| Type | Name | Description |
|---|---|---|
| **Variable** | `DOCKERHUB_USERNAME` | Docker Hub username (not sensitive, stored as a repository variable) |
| **Secret** | `DOCKERHUB_PASSWORD` | Docker Hub access token (sensitive, stored as an encrypted secret) |

> **Setup**: Go to *Settings → Secrets and variables → Actions* in your GitHub repository to configure these.

#### 4. Extract Metadata

```yaml
- name: Extract Metadata
  id: metadata
  uses: docker/metadata-action@v5
  with:
    images: tuftsttsrt/rstudio
    tags: |
      type=semver,pattern={{version}}
      type=raw,value=latest
```

Automatically generates Docker image tags from the release version:

| Release Tag | Generated Docker Tags |
|---|---|
| `v1.0.0` | `tuftsttsrt/rstudio:1.0.0`, `tuftsttsrt/rstudio:latest` |
| `v2.1.3` | `tuftsttsrt/rstudio:2.1.3`, `tuftsttsrt/rstudio:latest` |

- `type=semver,pattern={{version}}` strips the `v` prefix and uses the numeric version
- `type=raw,value=latest` always tags the newest release as `latest`

#### 5. Build & Push

```yaml
- name: Build & Publish Docker Image
  uses: docker/build-push-action@v5
  with:
    context: .
    push: true
    platforms: linux/arm64
    tags: ${{ steps.metadata.outputs.tags }}
    labels: ${{ steps.metadata.outputs.labels }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

| Parameter | Purpose |
|---|---|
| `context: .` | Uses the repository root as the Docker build context |
| `push: true` | Pushes the built image to Docker Hub |
| `platforms: linux/arm64` | Builds for ARM64 architecture |
| `tags` / `labels` | Uses the tags and OCI labels generated in step 4 |
| `cache-from` / `cache-to` | Uses [GitHub Actions cache](https://docs.docker.com/build/cache/backends/gha/) to store and reuse Docker layer cache between workflow runs, significantly speeding up rebuilds |

---

## How to Use This Demo

### Prerequisites

- A GitHub account
- A Docker Hub account (free tier works)

### Steps

1. **Fork this repository**

2. **Add secrets and variables** in your fork under *Settings → Secrets and variables → Actions*:
   - Variable: `DOCKERHUB_USERNAME` — your Docker Hub username
   - Secret: `DOCKERHUB_PASSWORD` — a Docker Hub [access token](https://docs.docker.com/security/for-developers/access-tokens/)

3. **Create a release** — go to *Releases → Draft a new release*, create a tag like `v1.0.0`, and publish it

4. **Watch the Action run** — go to the *Actions* tab to see the build progress

5. **Pull your image**:
   ```bash
   docker pull tuftsttsrt/rstudio:latest
   docker run -d -p 8787:8787 -e PASSWORD=yourpassword tuftsttsrt/rstudio:latest
   ```
   Then open `http://localhost:8787` in your browser (username: `rstudio`).

---

## Workflow Diagram

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────┐
│  Create Release  │────▶│  GitHub Actions runs  │────▶│  Docker Hub │
│  (e.g. v1.0.0)  │     │  docker_image.yml     │     │  Image push │
└─────────────────┘     └──────────────────────┘     └─────────────┘
                               │
                    ┌──────────┴──────────┐
                    │  1. Checkout repo    │
                    │  2. Setup Buildx     │
                    │  3. Login Docker Hub │
                    │  4. Extract metadata │
                    │  5. Build & push     │
                    └─────────────────────┘
```

---

## Key Concepts for the Talk

| Concept | Description |
|---|---|
| **GitHub Actions** | CI/CD platform built into GitHub — runs workflows in response to repository events |
| **Workflow** | A YAML file in `.github/workflows/` that defines automated jobs |
| **Runner** | The virtual machine that executes the workflow (GitHub-hosted or self-hosted) |
| **Secrets** | Encrypted values stored in GitHub, injected as environment variables at runtime |
| **Docker Buildx** | Extended Docker CLI plugin for advanced builds (caching, multi-platform) |
| **OCI Labels** | Standardized metadata embedded in the image (source URL, version, description) |
| **Layer Caching** | Reuses unchanged Docker layers across builds to save time |

---

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Docker Build Push Action](https://github.com/docker/build-push-action)
- [Rocker Project (R Docker images)](https://rocker-project.org/)
- [Docker Hub Access Tokens](https://docs.docker.com/security/for-developers/access-tokens/)

---

## License

This demo repository is intended for educational purposes at TTS Summit 2026.
