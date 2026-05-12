# bietlejuice-runtime

Databricks/Spark runtime components for `bietlejuice` pipelines.

This package, together with `bietlejuice-core`, is co-deployed to every
Databricks cluster via `default_libraries` (see `forno_conf.yml` /
`prod_conf.yml`). It is **not** published to PyPI; the wheel is built in CI
and uploaded to S3 for cluster init.

## Multi-DBR support

`bietlejuice-runtime` ships a single wheel that is intended to run on **all
currently supported Databricks Runtimes**:

| DBR        | Python  | Notes                                               |
| ---------- | ------- | --------------------------------------------------- |
| 12.2 LTS   | 3.9.21  | Supported; minimal env (see omissions below).       |
| 13.3 LTS   | 3.10.12 | Supported; smaller env than 16.4.                   |
| 16.4 LTS   | 3.12.3  | **Default for local dev and CI.**                   |

The wheel's `requires-python` is `>=3.9,<3.13` to cover all three.

### Why DBR-bundled libraries are not in `[project.dependencies]`

Libraries that the Databricks Runtime pre-installs at
`/databricks/python/...` (`numpy`, `pandas`, `pyarrow`, `psycopg2`,
`pydantic`, `cryptography`, `grpcio`, `urllib3`, ...) are intentionally
**absent** from `[project.dependencies]`. The cluster's pre-installed copy
wins on `sys.path` and the wheel never ships a duplicate.

This avoids ABI conflicts at runtime — most notably the aarch64 (Graviton)
`psycopg2` SIGABRT we hit when `psycopg2-binary` (which bundles its own
`libssl`/`libcrypto`) was deployed alongside DBR's system-linked
`psycopg2 2.9.3`. Removing it from the wheel lets DBR's copy resolve every
import.

## Local development architecture

`bietlejuice-runtime` is a **standalone uv project** — it is *not* a member
of the workspace defined in the repository's root `pyproject.toml`. The other
three packages (`bietlejuice-core`, `bietlejuice-airflow`,
`bietlejuice-compiler`) share a single workspace lockfile because their
dependencies are mutually compatible. Runtime cannot join them: `bietlejuice-airflow`
needs the modern Airflow 2.11 / Astro Runtime 13.4 dep tree, while runtime
needs to coexist with libraries DBR 12.2 / 13.3 / 16.4 ship from 2022/2023.
A single universal lockfile cannot satisfy both worlds.

The DBR-pinned dependencies live in **per-DBR sub-projects** under
[`envs/`](./envs):

```
packages/bietlejuice-runtime/
├── pyproject.toml          # the wheel project: broad requires-python, no DBR pins
├── src/bietlejuice/...
├── test/unit/...
└── envs/                   # local-only — never published, never built into wheels
    ├── dbr-12-2/pyproject.toml   # Python 3.9, DBR 12.2 LTS bundled libs
    ├── dbr-13-3/pyproject.toml   # Python 3.10, DBR 13.3 LTS bundled libs
    └── dbr-16-4/pyproject.toml   # Python 3.12, DBR 16.4 LTS bundled libs
```

Each `envs/dbr-X-Y` is a tiny pyproject whose only job is to feed `uv sync`
so the resulting `.venv` mirrors that DBR: the right Python, the bundled
library versions, plus `bietlejuice-runtime` and `bietlejuice-core` as
editable path installs. Because each env constrains itself to a single
Python (`>=3.12,<3.13` for dbr-16-4, etc.), uv resolves a single
`(Python × dependency-set)` combination per `.venv` — no conflicts.

The wheel is **always built from the top-level `bietlejuice-runtime`
pyproject**, never from an env. The envs are dev-only.

## Setup

### Default — DBR 16.4 LTS

`make install` syncs every package's venv, including
`packages/bietlejuice-runtime/envs/dbr-16-4/.venv`:

```bash
make install
```

This is what you want for day-to-day development. After it finishes:

| Path | Contents | Used by |
| ---- | -------- | ------- |
| `<repo>/.venv` (or `/home/vscode/.venv` in the devcontainer) | Workspace: core + airflow + compiler + dev tools | IDE, `make lint`, `make check-style` for those packages |
| `packages/bietlejuice-runtime/.venv` | Runtime broad versions + ruff/ty/pytest | `make check-style`, `make type-check` for runtime |
| `packages/bietlejuice-runtime/envs/dbr-16-4/.venv` | Runtime + DBR 16.4 LTS pinned libs + pytest | `make unit-tests` for runtime |

### Switching DBR

```bash
make sync-dbr DBR=12.2     # also creates/refreshes envs/dbr-12-2/.venv
make sync-dbr DBR=13.3     # ... and envs/dbr-13-3/.venv
make sync-dbr DBR=16.4     # default
```

`make unit-tests` always runs against `envs/dbr-16-4/.venv` because that is
the DBR production currently runs on. To run the same tests against an older
DBR:

```bash
make sync-dbr DBR=13.3
cd packages/bietlejuice-runtime && envs/dbr-13-3/.venv/bin/pytest -W ignore::DeprecationWarning
```

If `make sync-dbr DBR=12.2` reports `Python 3.9 not available`, uv will
auto-download it on first run. Same for 3.10 with DBR 13.3.

## IDE setup (Cursor / VS Code)

Three venvs means the editor needs a small bit of guidance to pick the right
one for each context.

### Default interpreter (workspace packages)

Point your editor at the workspace venv. The devcontainer settings already do
this via `python.defaultInterpreterPath`:

| Environment | Path |
| ----------- | ---- |
| Local       | `<repo>/.venv/bin/python` |
| Devcontainer | `/home/vscode/.venv/bin/python` |

This venv has every dependency for `bietlejuice-core`, `bietlejuice-airflow`
and `bietlejuice-compiler`. It does **not** have runtime's third-party deps
or DBR pins — those live in the runtime venvs.

### When you open a file under `packages/bietlejuice-runtime/`

You have two options:

1. **Recommended for everyday work:** keep the default workspace interpreter
   and let pyright resolve runtime imports via the `extraPaths` already
   configured in `.devcontainer/devcontainer.json`. Static analysis works,
   intellisense for runtime's own modules works. Some third-party imports
   (`spacy`, `presidio-analyzer`, `delta-spark`, ...) will be flagged
   unresolved unless you also do option 2 — they will not affect linting via
   ruff or type-checking via ty.

2. **Recommended when running runtime tests interactively:** override the
   interpreter for the `packages/bietlejuice-runtime/` folder. In
   Cursor/VS Code, open Command Palette → `Python: Select Interpreter` →
   choose `packages/bietlejuice-runtime/envs/dbr-16-4/.venv/bin/python`.
   This venv has every third-party dep installed; the test panel and "Run
   File" both work end-to-end.

The runtime sub-folder has its own `.venv` so per-folder interpreter selection
in the editor "just works" without polluting other packages' resolution.

## Refreshing a DBR env

Databricks publishes maintenance updates to LTS images occasionally. When
this happens:

1. Pull the latest **Installed Python libraries** table from the
   release-notes URL at the top of `envs/dbr-X-Y/pyproject.toml`
   (e.g. https://docs.databricks.com/aws/en/release-notes/runtime/16.4lts).
2. Update the matching version pins inside that env's `dependencies`.
3. Run `make sync-dbr DBR=<version>` to confirm the resolver is happy and
   regenerate `envs/dbr-X-Y/uv.lock`.
4. Commit the env's `pyproject.toml` and `uv.lock` together.

### Coverage caveat for older DBRs

`envs/dbr-12-2` and `envs/dbr-13-3` only pin libraries that those DBRs
actually pre-install. Anything the runtime code needs but the older DBR does
not ship (`pydantic` on 12.2, `opentelemetry-api` on either, ...) is omitted
and falls back to whatever the resolver picks. Tests against an older DBR may
need extra packages installed manually before they import cleanly. CI
currently exercises only `dbr-16-4`; matrix-testing against 12.2 / 13.3 is a
follow-up.

The omissions are documented as comments inside each env's `pyproject.toml`.
