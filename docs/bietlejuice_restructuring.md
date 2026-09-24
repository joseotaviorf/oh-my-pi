# bi-etl-ejuice: bietlejuice restructuring and developer environment

This document summarizes the work landed on `jose.rferreira/support_multiple_dbrs` relative to `master` (not an exhaustive file-by-file diff). It is aimed at engineers onboarding to the new layout and CI.

The work is stacked on `master` in four branches, in order:

1. `jose.rferreira/restructure_bietlejuice`
2. `jose.rferreira/devcontainer`
3. `jose.rferreira/improve_astro_environment`
4. `jose.rferreira/support_multiple_dbrs`

Each later branch includes everything from the ones before it.

---

## 1. Restructuring the `bietlejuice` code (monolith split, uv, and multi-DBR)

This section treats the **package split** and the **runtime / Databricks (multi-DBR) resolution** as one unit of work: the goal is a maintainable install and test model for **Airflow (modern)** and **Databricks (multiple DBR versions)** at the same time, without a single monolithic `bietlejuice/` tree or one lockfile that must satisfy every environment.

### 1.1 Six packages

The monolithic top-level `bietlejuice/` package is replaced by **six** packages under `packages/`, each with its own `pyproject.toml`, `src/` (or `src/bietlejuice/`), and tests (the old root `tests/` tree is removed; tests live next to the relevant package).

| Package | Role |
|--------|------|
| **bietlejuice-core** | Shared libraries: config, validation, paths, and code used in more than one context. `quintoandar-logger` is integrated via `uv` git source for dev/CI; wheel metadata omits it where Databricks `pip` cannot resolve private indexes. |
| **bietlejuice-airflow** | Airflow: DAG builder and anything that must import `apache-airflow` (currently aligned with **Airflow 2.11.2** / Astro Runtime 13.8.x). |
| **bietlejuice-airflow-operators** | Databricks / EMR Airflow operators (vendored; previously cloned from external plugin repos). |
| **bietlejuice-airflow-plugins** | Airflow plugins (extra links, etc.). |
| **bietlejuice-runtime** | Databricks/Spark: PySpark, Delta-adjacent stack, Qube jobs, UDFs, and code meant to run on clusters. The **published wheel** is intentionally not the same dependency graph as Airflow’s. |
| **bietlejuice-compiler** | CI and local tooling: `create-dag-files`, SQL/Yaml validation, metadata and pipeline scripts. Declares **Airflow 2.11.2** as a real dependency so `airflow` imports work in `make create-dag-files` and similar steps. |

The **root** of the repository is not an installable Python package. A **root** `pyproject.toml` and **`uv.lock`** define a **uv workspace** for the five members that can share a resolver (see below). **bietlejuice-runtime is not a workspace member** (see multi-DBR).

### 1.2 Build, release, and path behavior

- **Wheels:** `make build` uses `uv build` to produce **bietlejuice-core** and **bietlejuice-runtime** under **`dist/`** for Databricks/EMR-style installation. The Airflow wheel is **not** part of that publish path; Airflow code ships with the **Astronomer DAG bundle** (merged tree from core + airflow `src/bietlejuice/`), not as a library wheel on workers.
- **Legacy alias:** the old single **bi_etl_ejuice-latest** wheel naming is **retired**; consumers are expected to use the **core** and **runtime** wheel artifacts and the DAG delivery pipeline documented in **Woodpecker** `release.yml`.
- **Imports and paths:** code moves toward **direct module imports** and explicit `__all__` where needed; path discovery uses **`DAG_PACKAGES_ROOT`** and `ConfigurationService` fallbacks so the dagbag and Qube do not rely on `__file__` guessing. **`.airflowignore`** is restored in the new layout.
- **Config:** environment YAML and related files follow **`BIETLEJUICE_CONFIG_ROOT`** and live under a **`config/`**-style layout in the `bietlejuice` packages.

### 1.3 Multi-DBR and `bietlejuice-runtime`

A **single** uv lockfile cannot satisfy **old DBR-bundled libraries** and **Apache Airflow 2.11** (used locally and in CI) at the same time. The fix is:

- **Workspace (root `pyproject.toml`):** members are **bietlejuice-core**, **bietlejuice-airflow**, **bietlejuice-airflow-operators**, **bietlejuice-airflow-plugins**, and **bietlejuice-compiler**. The root file documents **`[tool.uv] override-dependencies`**, `index-strategy`, and **`[tool.uv.sources]`** (e.g. `quintoandar-logger` from git) for those members.
- **bietlejuice-runtime** is a **standalone** uv project: its own **`uv.lock`**, not listed under `[tool.uv.workspace] members`, so Databricks-specific pins do not fight the Airflow workspace.
- **Per-DBR environments:** under `packages/bietlejuice-runtime/envs/` there are small **shim** projects (e.g. `dbr-12-2`, `dbr-13-3`, `dbr-16-4`), each with its own **`.venv`**, the **Python version** that matches that DBR, and dependencies aligned with what the cluster preinstalls. **`make sync-dbr DBR=12.2|13.3|16.4`** (default **16.4**) selects the corresponding env. **Unit tests and core model tests** for runtime run with the **dbr-16-4** interpreter and **`PYSPARK_PYTHON` / `PYSPARK_DRIVER_PYTHON`** set to that env’s binary so Spark workers do not pick an unrelated `python3` from `PATH`. CI **syncs dbr-16-4** in the test pipeline; a full **matrix** for 12.2/13.3 in CI is left as a follow-up.
- **Published wheel `Requires-Dist`:** the runtime wheel is trimmed so cluster `pip` installs and DBR preloads do not pull conflicting or redundant packages (e.g. components that the cluster already provides, or that cannot be resolved the same way across all targets). **Relaxation** of floors in `bietlejuice-core` and runtime (e.g. PyYAML) and careful handling of internal client packages is part of making locks resolvable across **Airflow**, **DBR**, and legacy **QuintoAndar** libraries. Operational details of **psycopg2** on **ARM/Graviton** are documented in the relevant commit messages, not here.

### 1.4 Tooling migration (same restructuring effort)

- **Package management:** **uv** (`uv sync`, `uv run`, `uv build`, `uv export`) replaces the old **pip**-centric flows at the monolith root.
- **Lint / format:** **Ruff** replaces **Black/Flake8**; see [Ruff](#7-ruff).
- **Types:** **ty** (Astral) is wired for incremental signal; see [ty](#8-ty-type-checker).
- **SQL:** **sqlfluff** runs from **bietlejuice-compiler** against `dags/`.
- **Tests:** **pytest** + **pytest-cov** are configured per package in `pyproject.toml`.

---

## 2. Dev container support (branch: `jose.rferreira/devcontainer`)

- **Container image** built from a **root Dockerfile** (repo is build context) with **BuildKit** secret for **`GITHUB_TOKEN`** so private Git dependencies do not become plain build args in image metadata.
- **Pre-baked** system dependencies, **Java** (for Spark tests), and a **warmed uv cache** so the **post-create** step can `uv sync` in seconds.
- **`UV_PROJECT_ENVIRONMENT=/home/vscode/.venv`** so the in-container venv is stable and does not overwrite or collide with a host **`.venv`** when switching between host and container.
- **Post-create** script re-links editable workspace installs to **bind-mounted** source paths.
- **Docker-outside-of-Docker (DooD)** feature is enabled so **Astro CLI** can run Docker from inside the devcontainer (see [Local Astro](#3-local-astronomer-astro-support)).
- **Workspace** root **`uv.lock`** locks the **five** workspace members together.
- **IDE (VS Code–compatible, including Cursor):** see [Dev container and IDE settings](#10-dev-container-and-ide-settings).

---

## 3. Local Astronomer (Astro) support

- **Base image** aligned with **Astronomer Astro Runtime 13.8.0** and **Airflow 2.11.2**, built from **`astro/Dockerfile`** (repo-root context) — same image as the Astro "dev" deployment.
- **`make run-local-environment`** builds **`bietlejuice-airflow:local`**, then runs **`astro dev start --image-name`** from **`astro/`**. Packages are installed in the image; **core / airflow / operators / plugins** `src/` plus **`dags/`** and compiler **`scripts/`** are **bind-mounted** with **`PYTHONPATH`** so live edits win over site-packages.
- **Astro CLI** is used for `astro dev start` / `restart` / `stop` / `kill`. **`verbose=`** is supported on `run-local-environment` and `restart-local-environment`. **Health-check timeout** workarounds exist for **DooD** (webserver on `127.0.0.1` may not be reachable from inside the devcontainer the way `astro` expects; the Makefile verifies running containers and waits for `airflow db check`).
- **Host** **`DATABRICKS_*`** (and `GITHUB_TOKEN`) are forwarded for consistent behavior with the host. **`VAULT_TOKEN`** is loaded from `qli` (`astro/scripts/export_qli_vault_token.py`) so local Airflow resolves variables via the same forno Vault path as the forno Astronomer deployment. Connections stay local (personal Databricks token).

### 3.1 Astro "dev" deployment (`.woodpecker/development.yml`)

Isolated from forno/prod. On push to the **`development`** branch:

- `make create-astro-dag-files` — regenerate parse-time manifests + **domain bundles** + **migration exec-passthrough bundles** (no per-DAG stubs).
- Filtered rsync into `astro/dags/` then `astro deploy --dags` to the Astronomer "dev" deployment.

Forno/prod continue to use **`make create-dag-files`** via `.woodpecker/release.yml` (unchanged until the follow-up CI PR).

---

## 4. Makefile (high level)

| Area | Behavior |
|------|----------|
| **`build-devcontainer`** | Builds the dev image with the BuildKit secret; tags **`bi-etl-ejuice-devcontainer:latest`**. |
| **`build-astro-local-image`** | Builds **`bietlejuice-airflow:local`** from **`astro/Dockerfile`** (repo-root context). |
| **`build`** | `uv build` for **bietlejuice-core** and **bietlejuice-runtime** to **`dist/`**. |
| **`install`** | `uv sync` for each project; for runtime uses **`env -u UV_PROJECT_ENVIRONMENT`** in devcontainer-friendly mode; also syncs **`envs/dbr-16-4`** for default test runs. |
| **`sync-dbr`** | `DBR=12.2\|13.3\|16.4` selects `packages/bietlejuice-runtime/envs/dbr-…`. |
| **`run-local-environment` / `restart-local-environment`** | Optional `verbose=`; build image then `astro` from **`astro/`** with `--image-name`; DooD health-check note; post-start **`airflow db check`** wait. |
| **Lint** | `lint` / `check-style` / `fix-style` → per-package **ruff format** and **ruff check** on `src/` and `test/`. |
| **`type-check`** | Per-package **`ty check src/`**. |
| **SQL** | `lint-sql` / `check-sql` via **bietlejuice-compiler** + **sqlfluff** on `dags/`. |
| **`unit-tests` / `core-model-*`** | **Runtime** tests use **`envs/dbr-16-4/.venv`**, with **PYSPARK_*** set to that interpreter. |
| **S3 / upload** | `uv run --project packages/bietlejuice-runtime\|bietlejuice-compiler` and paths under **`packages/`**. |
| **General** | `PYTHONPATH` still includes the compiler for script imports; developer flows assume **uv** instead of global `pip` at the repo root. |

---

## 5. Woodpecker (CI)

- Steps use **`pip install uv`** and **`uv sync --directory packages/...`**. The **tests** `setup` step, on the tip branch, also **`uv sync` `packages/bietlejuice-runtime` and `packages/bietlejuice-runtime/envs/dbr-16-4`** so `make unit-tests` matches **DBR 16.4**-like imports.
- **`event: [push, pull_request]`** on `when.path` so path filters use the **full PR diff** (not only the last commit); documented in pipeline headers.
- **Unit and integration** test steps also run on changes to **root/ package `pyproject.toml`** or **`uv.lock`**.
- **Lint** runs **`check-style-python`** (packages, compiler scripts, repo-root tests) and **`check-style-dags-python`** (`dags/`); **`type-check-python`** uses **`failure: ignore`** (informative only).
- Shared **setup** steps before parallel jobs reduce venv **race** issues.
- **`release.yml`:** unified **path anchors** for the **wheel** pipeline and the **DAG-bundle** chain so a change only in library code still runs the full deploy tail; `make build` → two wheels in `dist/`; **stage** step merges `packages/bietlejuice-core` and `packages/bietlejuice-airflow` **`bietlejuice` trees** for the S3 path Astronomer expects; Forno/Prod **`*-latest-*` wheel** aliasing. Images generally use **Python 3.12** on **Debian bookworm**-class bases.

---

## 6. uv: how the repo is wired

- **Root workspace:** `bietlejuice-core`, `bietlejuice-airflow`, `bietlejuice-airflow-operators`, `bietlejuice-airflow-plugins`, `bietlejuice-compiler` + **`uv.lock`**. **bietlejuice-runtime** is **outside** that member list with its **own lock**.
- **Rationale (short):** Airflow 2.11, multiple DBRs, and legacy internal packages cannot share one resolver graph without **overrides** and a **split** lock for runtime.
- **Per-DBR venvs:** `packages/bietlejuice-runtime/envs/dbr-12-2|dbr-13-3|dbr-16-4` — one venv per DBR for **repro tests** and local parity; default **16.4** in **Makefile** and **CI** test setup.

---

## 7. Ruff

- **Single config:** root **`pyproject.toml`** `[tool.ruff]` (line length 88, `py310`, rules E4/E7/E9/F/I/UP, DBR-related UP ignores, Databricks `builtins`, per-file ignores for `dags/` and compiler `scripts/`). See **[`docs/ruff.md`](ruff.md)** for the full audit table and Makefile scope.
- **`make check-style`:** `packages/*/src`, `packages/*/test`, `packages/bietlejuice-compiler/scripts` — enforced in Woodpecker (`check-style-dags` covers `dags/` separately).
- **`make check-style-dags`:** **`dags/`** Spark jobs and DAG Python — enforced in Woodpecker (`check-style-dags-python`).
- **`make lint`** / **`make fix-style`** and **`make lint-dags`** / **`make fix-style-dags`** apply format and safe autofix for the same paths.

---

## 8. ty (type checker)

- **`make type-check`** runs **Astral `ty`** on each package’s **`src/`**, with **`[tool.ty.environment]`** per package where set.
- **CI** runs **`type-check` with `failure: ignore`** to provide **fast signal** without blocking merges while typing coverage improves.

---

## 9. Testing (summary)

- Tests are **per-package**; each `pyproject.toml` defines pytest and coverage.
- **Runtime** tests in CI and default local `make install` assume **`dbr-16-4`** is synced; **PYSPARK_*** point at that venv.
- **Core model** and **validations** paths in Woodpecker point to **`dags/core/**` and the new `packages/.../core_models/` locations.

---

## 10. Dev container and IDE settings

- **Interpreter:** fixed to **`/home/vscode/.venv/bin/python`**. **`remoteEnv`** forwards **GITHUB** / **DATABRICKS**-related variables and sets **`UV_PROJECT_ENVIRONMENT`**. **`postCreateCommand`** runs **`.devcontainer/post-create.sh`**.
- **Editor stack:** extensions include **Python**, **Cursor Pyright** (`anysphere.cursorpyright`), **Ruff**, TOML, YAML, SQL tools, **SQLFluff LSP**.
- **Analysis:** **`python.analysis.extraPaths` / `basedpyright.analysis.extraPaths`** list all six **`packages/*/src`**; venv resolution points at **`/home/vscode/.venv`**.
- **Tests:** pytest enabled with **`--import-mode=importlib`**, discovery from **`packages/`** so the Test view sees all package test trees.
- **Formatting:** Ruff as default Python formatter, **format on save**.
- **`python.languageServer`** is set to **None** so the primary analysis comes from **Cursor Pyright** without duplicating Pylance. This is **editor-specific** to Cursor; VS Code can use a similar pattern with the Pyright extension of choice.

---

## 11. Other notes

- **Internal HTTP/API client** refactors (auth, pagination) and tests landed with the restructure to clarify boundaries.
- **Java:** CI test images set **`JAVA_HOME`** to **OpenJDK 17** for Spark; devcontainer orbits may use a newer JDK for other tooling—confirm `Makefile` and `.woodpecker` if you need a single **Java** version org-wide.
- If something is **not** in this document (exact pin, single-file move), use **`git log master..jose.rferreira/support_multiple_dbrs`** and the per-topic commits.

---

*Last updated to reflect the `jose.rferreira/support_multiple_dbrs` line vs `master` (stacked behind `restructure_bietlejuice`, `devcontainer`, and `improve_astro_environment`). Update this file when that branch or its successors change materially.*
