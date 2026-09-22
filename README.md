<table align="center">
  <tr>
    <th>Build Status</th>
  </tr>
  <tr>
    <td>
        <a href="https://woodpecker.shared.quintoandar.com.br/quintoandar/bi-etl-ejuice">
            <img src="https://woodpecker.shared.quintoandar.com.br/api/badges/quintoandar/bi-etl-ejuice/status.svg" />
        </a>
    </td>
  </tr>
</table>

# bi-etl-ejuice

Airflow DAGs, Spark jobs, and supporting libraries for QuintoAndar’s data platform (orchestrated in Airflow, executed on Databricks and related runtimes).

<img src="bietlejuice.jpg" width="200">

---

## Overview

- **`dags/`** — Pipelines by **business domain** and **DAG name**. A typical folder includes:
  - `*_declaration.yml` — Airflow schedule and workflow; generated `*_dag.py` from the DAG builder
  - **`queries/`** — SQL by layer (where applicable)
  - **`metadata/`** — Governance YAML (one per table, paired with `queries/`)
  - **`data_quality/`** — (optional) Great Expectations specs
  - **`spark_jobs/`** — (optional) PySpark for custom Spark jobs
  - **`schemas/`** — (core model DAGs) JSON schema files
  - **`dags/qube/`** — Qube dimensions / measures / metrics: declarations here; Spark implementation lives under **`packages/`** (not the `queries/` + `metadata/` layout above)
- **`packages/`** — Python code for **`bietlejuice`**, split into **six** installable projects so **Airflow** and **Databricks** can depend on different pins without one giant package:
  - **`bietlejuice-core`** — shared config, validation, and utilities
  - **`bietlejuice-airflow`** — DAG builder, Airflow integration (Airflow 2.11.x / Astro Runtime 13.8.x)
  - **`bietlejuice-airflow-operators`** — Databricks / EMR Airflow operators
  - **`bietlejuice-airflow-plugins`** — Airflow plugins (extra links, etc.)
  - **`bietlejuice-runtime`** — Spark, Qube, UDFs, Databricks-side code (separate `uv` lock; optional per-**DBR** venvs under `envs/`)
  - **`bietlejuice-compiler`** — `create-dag-files`, validation scripts, SQL tooling

  Five packages are uv workspace members; **runtime** is standalone.

**Tooling:** dependencies and tasks are managed with **[uv](https://docs.astral.sh/uv/)**; **Ruff** replaces Black/Flake8; tests run with **pytest** per package. CI uses **Woodpecker** (see `.woodpecker/`).

For **design decisions, CI behavior, multi-DBR layout, and IDE details**, see **[`docs/bietlejuice_restructuring.md`](docs/bietlejuice_restructuring.md)**.

---

## Clone the repository

If you are reading this on GitHub, start by cloning the repo and entering the project directory:

```bash
git clone git@github.com:quintoandar/bi-etl-ejuice.git
cd bi-etl-ejuice
```

(Use HTTPS if you prefer: `https://github.com/quintoandar/bi-etl-ejuice.git`.)

---

## Recommended: Dev container (primary)

**Prefer the dev container** for day-to-day work. It bakes in **uv**, **Java**, OS packages, a warmed wheel cache, and a single **Python** environment so everyone matches CI and you avoid “works on my machine” drift.

### What you need on your machine (host)

Almost everything runs **inside Docker**; the host is only there to run containers and to talk to GitHub.

| On the host                             | Why                                                                                                                                                                                                                                                                                          |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Docker**                              | Build and run the dev container image, and (with Docker-outside-of-Docker) run **local Airflow (Astro)** from inside the container. Use a current **Docker with BuildKit** (default in recent Docker Desktop / Engine) so the image build can use the **GITHUB_TOKEN** secret.               |
| **Git**                                 | Clone and version control.                                                                                                                                                                                                                                                                   |
| **Editor**                              | [Cursor](https://cursor.com/) (recommended) or [VS Code](https://code.visualstudio.com/) with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) installed, so you can open the folder *in* a dev container (see below). |
| **Credentials (environment variables)** | See below.                                                                                                                                                                                                                                                                                   |

**You do not** need a separate **Python**, **uv**, or **Java** install on the host for normal development in the dev container—the **Dockerfile** and `postCreateCommand` set those up. Optional **Astro CLI** and similar tooling are expected to be used **from the container** (or installed there as in the current `.devcontainer` setup) when you run `make` targets.

### Credentials (host shell → passed into the container / build)

- **`GITHUB_TOKEN`** — **Required** for the image build and for `uv sync` when private Git dependencies (e.g. `quintoandar-logger`) are resolved. Export it in your **host** shell before `make devcontainer-build` or let your editor pass it when building the devcontainer.
- **`DATABRICKS_TOKEN`**, **`DATABRICKS_USERNAME`** — Optional on the **host**; the devcontainer forwards them so `make run-local-environment` and Databricks usage behave like on a bare machine.

`make setup-local-variables` can help persist GitHub/Databricks env vars in your host shell if you are not using another secrets manager.

### Open the project in the dev container (recommended: IDE)

**Cursor** and **VS Code** can build and start the dev container the **first time you open the project** in the container (no `make` step required for that first build), as long as **Docker** is running and your credentials are available.

- **Cursor** — Open the cloned repo, then use the command palette: **“Dev Containers: Reopen in Container”**. The **first** open **builds the image automatically** (one-time, can take several minutes); then **`.devcontainer/post-create.sh`** runs `uv sync`. See [Dev Containers in VS Code](https://code.visualstudio.com/docs/devcontainers/containers) for the same workflow in compatible editors.
- **VS Code** — Install the official [**Dev Containers** extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) (ID `ms-vscode-remote.remote-containers`, published by Microsoft). Open the repo folder, then **Dev Containers: Reopen in Container**; the first run builds the image, then `post-create` runs.

Set **`GITHUB_TOKEN`** on the host (and optional **`DATABRICKS_*`**) so the build and `uv sync` can reach private Git dependencies (see the **Credentials** subsection above).

1. From a terminal **inside the container**, after checkout or when dependencies change:

   ```bash
   make install
   ```

2. **Local Airflow** is supported from inside the container via **Docker-outside-of-Docker** (the Docker socket is mounted so `astro` uses the host engine). See [Local Airflow (Astronomer Astro)](#local-airflow-astronomer-astro).

Editor defaults (Ruff, Pyright/Cursor Pyright, pytest under `packages/`) are described in **[`docs/bietlejuice_restructuring.md`](docs/bietlejuice_restructuring.md)** (*Dev container and IDE settings*).

### Build the dev container image from the command line (optional)

If you prefer to **pre-build** the image, or you are not using the IDE flow:

1. Export **`GITHUB_TOKEN`** in your host shell (and optional **`DATABRICKS_*`**).
2. Run (BuildKit passes the token as a **secret**, not a build-arg):

   ```bash
   make devcontainer-build
   ```

3. In **Cursor** or **VS Code**: **“Dev Containers: Reopen in Container”** to attach to that image, then `make install` inside the container when needed.

---

## Alternative: develop on the host (no dev container)

Use this if you **cannot** use Docker for development or you strongly prefer a native environment.

### What you need on the machine

| Requirement     | Notes                                                                                                                                                                                                                                   |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **uv**          | [Install uv](https://docs.astral.sh/uv/getting-started/); it drives `make install`, `uv run`, and wheel builds.                                                                                                                         |
| **Python**      | Versions are pinned per `packages/*/pyproject.toml` (workspace packages are typically **3.10+**; **bietlejuice-runtime** also uses **per-DBR** venvs under `packages/bietlejuice-runtime/envs/` for cluster parity: 3.9 / 3.10 / 3.12). |
| **Java**        | **JDK 17** for Spark-related tests and tooling (CI uses OpenJDK 17 for those steps).                                                                                                                                                    |
| **Docker**      | **Only if** you use **local Airflow (Astro)** — same engine as today; you still run containers on the host.                                                                                                                             |
| **Credentials** | **`GITHUB_TOKEN`** for `uv sync` and private git deps. **`DATABRICKS_TOKEN` / `DATABRICKS_USERNAME`** for local Airflow and Databricks (`make setup-local-variables` can help).                                                         |

From the **repository root**:

1. **Install** all package venvs (workspace + **bietlejuice-runtime** + default **dbr-16-4** test env):

   ```bash
   make install
   ```

2. **Tests and style:**

   ```bash
   make check-style
   make tests   # unit-tests + unit-tests-dags
   ```

3. **Optional —** switch the DBR mirror venv (default **16.4**):

   ```bash
   make sync-dbr DBR=12.2   # or 13.3 / 16.4
   ```

4. **Regenerate Airflow `*.py` from declarations** when needed:

   ```bash
   make create-dag-files
   # or: make create-dag-files dag_name=<name>
   ```

For all targets, see the root **`Makefile`**.

---

## Local Airflow (Astronomer Astro)

Local Airflow uses the **`astro/`** project and the same **`astro/Dockerfile`** as CI/prod. Packages are baked into the image; **core / airflow / operators / plugins** sources (plus `dags/` and compiler `scripts/`) are **bind-mounted** for live edit/parse feedback.

Typical flow (repo root, **in the dev container or on the host** if Docker is available):

1. `make setup-local-variables` (once) — GitHub / Databricks tokens. Also run `qli login` so local Airflow can resolve variables via Vault (forno path).
2. `make create-dag-files` when declarations or the DAG builder change (also regenerates gitignored parse-time manifests).
3. `make run-local-environment` — builds `bietlejuice-airflow:local` from repo root, injects `VAULT_TOKEN` from qli, then `astro dev start --image-name` from `astro/`. Optional `verbose=1`. Offline fallback: `make refresh-local-variables` then the seed import.
4. UI: **http://localhost:8080** (check Astro’s output for the exact URL/port).

Install the [**Astro CLI**](https://www.astronomer.io/docs/astro/cli/install-cli/) where you run the commands (in many setups that is **inside the devcontainer**; on the host-only path, install it on the host). More context: [`astro/README.md`](astro/README.md).

---

## Useful commands (quick reference)

| Command                                      | Purpose                                                                   |
| -------------------------------------------- | ------------------------------------------------------------------------- |
| `make install`                               | Sync all packages + default **dbr-16-4** env for runtime tests.           |
| `make check-style` / `make fix-style`        | Ruff format + lint on packages `src/`/`test/` and compiler `scripts/`. |
| `make check-style-dags` / `make fix-style-dags` | Ruff format + lint on `dags/` (CI: `check-style-dags-python`). |
| `make type-check`                            | `ty` on each package (optional local signal; CI is non-blocking).         |
| `make unit-tests` / `make unit-tests-dags` / `make tests` | Package pytest (`unit-tests`); DAG spark-job tests under `runtime/test/dags` (`unit-tests-dags`, separate Woodpecker step); `tests` runs both. Runtime uses **dbr-16-4**. |
| `make integration-tests` | Integration pytest (core). |
| `make build`                                 | Build **bietlejuice-core** and **bietlejuice-runtime** wheels to `dist/`. |
| `make run-local-environment`                 | Start local Airflow via Astro.                                            |

For SQL style on `dags/`, see `make check-sql` / `make lint-sql` in the **Makefile**.

---

To run a single package or DAG test folder:

```bash
    uv run --directory packages/bietlejuice-core pytest test/unit/services/test_configuration_service.py -v
```

---

## Configuring a Google Chat webhook for alerts

Spark jobs and data-quality checks send alerts through `GChatService`, resolved from a human-readable channel keyword (e.g. `AUTHX_ALERTS`) to a webhook URL fetched from Databricks Secrets. Adding a new channel touches three places: Google Chat, Vault, and one enum in this repo.

1. **Create the webhook in Google Chat.** In the target space, open **Apps & integrations** → **Add webhooks**, name it, and copy the generated URL. Each channel that should receive alerts needs its own webhook.

2. **Store the URL in Vault, one secret per environment.** Add it at:

   ```
   apps/<env>/bi-etl-ejuice/WEBHOOK_NAME
   ```

where `<env>` is `prod` or `forno`, and `WEBHOOK_NAME` is the secret name. This must be requested via a PR in the [`infrastructure`](https://github.com/quintoandar/infrastructure) repo — see [#41477](https://github.com/quintoandar/infrastructure/pull/41477) for an example. Vault secrets under `apps/<env>/bi-etl-ejuice/*` are synced into the `quintoandar` scope in Databricks Secrets, which is what `dbutils.secrets.get(scope="quintoandar", key=...)` reads at runtime (see [`AlertChannelService`](packages/bietlejuice-runtime/src/bietlejuice/services/messaging_services/alert_channel_service.py)).

3. **Register the channel keyword** in [`GchatWebhooksEnum`](packages/bietlejuice-runtime/src/bietlejuice/base/notification/gchat_webhooks_enum.py):

   ```python
   class GchatWebhooksEnum:
       ...
       MY_TEAM_ALERTS = "GCHAT_MY_TEAM_ALERTS_WEBHOOK"  # must match the Vault secret name
   ```

The class attribute value must be the exact Vault/Databricks-Secrets key from step 2. The attribute *name* (`MY_TEAM_ALERTS`) is the keyword used elsewhere — e.g. as `alert_channel:` in a `data_quality/*.yml` file, or as the `channel` argument to a monitor.

Once all three are in place, `AlertChannelService(dbutils=...).get_gchat_webhook_url(channel_keyword="MY_TEAM_ALERTS", ...)` resolves the keyword to the secret key, fetches it from Databricks Secrets, and `GChatService.send_message` posts to it.

---

## Hotfixes

Urgent production path: [Hotfix flow (Google Doc)](https://docs.google.com/document/d/13_0MoPv_R5eYk647v7BRQSp4O6P-mcr3AdouC8gwXVk/edit#heading=h.otmv9f3bbomh).
