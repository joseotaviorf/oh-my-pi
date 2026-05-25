---
name: generate-unit-test
description: Generate correctly-patterned unit tests for bietlejuice modules. Selects the right test pattern (Qube unittest.TestCase vs pytest class) based on the source module, sets up correct mocks, and mirrors the file structure. Use when the user asks to write, generate, or add unit tests for a bietlejuice module.
---

# Generate a Unit Test

## Step 0 — TDD mode: determine whether implementation exists

Before reading any source code, answer: **does the implementation file already exist?**

### Case A — New feature (implementation does not exist yet)
Generate the test file **first**, before any implementation is written. Use `@pytest.mark.xfail(reason="not yet implemented", strict=True)` on every stub so CI stays green while work is in progress but will fail loudly if an xfail unexpectedly passes (which signals the test was written incorrectly).

```python
import pytest

class TestMyNewClass:

    @pytest.mark.xfail(reason="not yet implemented", strict=True)
    def test_happy_path(self):
        # arrange
        # (describe the inputs the implementation will receive)
        # act
        # result = MyNewClass().execute(...)
        # assert
        # assert result == expected_value
        raise NotImplementedError

    @pytest.mark.xfail(reason="not yet implemented", strict=True)
    def test_invalid_input_raises(self):
        raise NotImplementedError
```

Commit the test file. Then hand off to the implementation step (the developer or the next AI turn writes the code to make the tests pass).

### Case B — Existing module (implementation already exists)
Proceed directly to Step 1. If this is a **bug fix**, add a regression parametrize case for the broken input before modifying the implementation.

```python
@pytest.mark.parametrize("broken_input,expected_error", [
    (None, ValueError),           # regression: issue #123 — None caused AttributeError
    ("", ValueError),
])
def test_validate_raises_on_bad_input(self, broken_input, expected_error, my_fixture):
    with pytest.raises(expected_error):
        my_fixture.validate(broken_input)
```

---

## Step 1 — Read the source module

Read the target source file. Identify:
- All public functions and classes to test
- External dependencies imported (PySpark `F.*`, services, clients, loaders)
- Arguments and return types of each function/method

## Step 2 — Determine the test pattern

| Source path starts with... | Test pattern |
|----------------------------|-------------|
| `bietlejuice/qube/` | **Pattern A**: `unittest.TestCase` + `@patch` for `F.*` |
| `bietlejuice/base/airflow/` | **Pattern B**: pytest class + `@mock.patch.object` + fixtures |
| `bietlejuice/base/` (non-airflow) | **Pattern B**: pytest class |
| `bietlejuice/services/` | **Pattern B**: pytest class |
| `bietlejuice/pipeline/` | **Pattern B**: pytest class |

## Step 3 — Determine the test file path

Pick the **package** from the source path, then mirror under that package’s `test/unit/` (or `test/dags/` / `test/core_model_dags/` for DAG jobs):

| Source lives in… | Test root |
|------------------|-----------|
| `packages/bietlejuice-runtime/src/bietlejuice/` (qube, api, pipeline, most `base/`) | `packages/bietlejuice-runtime/test/unit/` |
| `packages/bietlejuice-core/src/bietlejuice/` (services, some `base/airflow/dag_builders/`) | `packages/bietlejuice-core/test/unit/` |
| `packages/bietlejuice-airflow/src/bietlejuice/` (task creators, task groups, datasets) | `packages/bietlejuice-airflow/test/unit/` |
| `dags/{domain}/…/spark_jobs/load_*.py` | `packages/bietlejuice-runtime/test/dags/{domain}/…/spark_jobs/` |
| `dags/core/core_{entity}/spark_jobs/` | `packages/bietlejuice-runtime/test/core_model_dags/unit/core/core_{entity}/spark_jobs/` |
| `dags/{domain}/…/*.py` (Airflow DAG module, not a Spark job) | `packages/bietlejuice-airflow/test/unit/dags/{domain}/…/` |

Examples:
```
packages/bietlejuice-runtime/src/bietlejuice/qube/jobs/metrics/build_metric.py
→ packages/bietlejuice-runtime/test/unit/qube/test_build_metric_unit.py

packages/bietlejuice-airflow/src/bietlejuice/base/airflow/dag_builders/main_builder/dag_yaml_parser.py
→ packages/bietlejuice-airflow/test/unit/base/airflow/dag_builders/main_builder/test_dag_yaml_parser.py

packages/bietlejuice-core/src/bietlejuice/services/configuration_service.py
→ packages/bietlejuice-core/test/unit/services/test_configuration_service.py
```

## Step 4 — Write the test file

### Pattern A (Qube): `unittest.TestCase` + mock PySpark

```python
import unittest
from unittest.mock import MagicMock, patch

from bietlejuice.qube.jobs.{module} import {function_or_class}


class Test{FunctionOrClass}(unittest.TestCase):

    @patch("bietlejuice.qube.jobs.{module}.F.col")
    @patch("bietlejuice.qube.jobs.{module}.F.when")
    def test_{scenario}(self, mock_when, mock_col):
        # arrange
        mock_col.return_value = MagicMock()
        mock_when.return_value = MagicMock()
        input_df = MagicMock()
        input_df.columns = ["col_a", "col_b"]

        # act
        result = {function_or_class}(input_df, ...)

        # assert
        mock_col.assert_any_call("col_a")
        self.assertEqual(result, expected_value)

    def test_{edge_case}(self):
        # arrange / act / assert pattern
        ...
```

Mock at the **import location**, not definition: `"bietlejuice.qube.jobs.{module}.F.col"`.

### Pattern B (DAG builder / services): pytest class

```python
from unittest import mock
import pytest

from bietlejuice.base.{module} import {ClassName}


@pytest.fixture
def my_instance():
    return {ClassName}(...)


class Test{ClassName}:

    @mock.patch("bietlejuice.base.{module}.ExternalDep")
    @mock.patch.object(SomeDependency, "method_name")
    def test_{scenario}(self, mock_method, mock_dep, my_instance):
        # arrange
        mock_method.return_value = "expected"

        # act
        result = my_instance.do_thing()

        # assert
        assert result == "expected"
        mock_method.assert_called_once_with("arg")

    @pytest.mark.parametrize("input,expected", [
        ("valid_input", True),
        ("invalid_input", False),
    ])
    def test_{scenario}_parametrized(self, input, expected, my_instance):
        assert my_instance.validate(input) == expected
```

## Step 5 — Check and update conftest.py

If a `conftest.py` doesn't exist in the test folder, check the parent. For Qube tests, ensure a session-scoped real Spark fixture exists:

```python
# packages/bietlejuice-runtime/test/unit/qube/conftest.py
import pytest
from pyspark.sql import SparkSession

@pytest.fixture(scope="session")
def spark():
    spark = (
        SparkSession.builder.appName("QubeTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.ui.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()
```

For DAG builder tests, add fixtures for the class under test:
```python
# packages/bietlejuice-airflow/test/unit/base/airflow/.../conftest.py
import pytest
from bietlejuice.base.airflow... import {ClassName}

@pytest.fixture
def {instance_name}():
    return {ClassName}(dag_name="test_dag")
```

## Step 6 — Verify

```bash
uv run --directory packages/bietlejuice-runtime pytest test/unit/path/to/test_file.py -v
# (use bietlejuice-core | bietlejuice-airflow | bietlejuice-compiler | emr-cli as appropriate)
```

Fix any import errors (usually missing `sys.modules` mocks at the top-level conftest).

## Rules
- Always use Arrange / Act / Assert structure.
- Never test private methods directly; test through the public API.
- One test class per public class/function in the source module.
- Test at least: the happy path, one error/edge case, and any parametrized branches.

## TDD Checklist — verify before finishing

- [ ] Test file path mirrors source path under the correct package `test/` tree (Step 3 naming)
- [ ] Test file was created before or alongside the implementation (Step 0 — not as a follow-up)
- [ ] All `@pytest.mark.xfail(strict=True)` stubs have been converted to real assertions before the PR is merged
- [ ] Every public method/function has a happy-path test AND at least one error/edge-case test
- [ ] Bug fixes include a regression parametrize case pinning the broken input
- [ ] Public interface changes are covered by updated tests for all affected call sites
- [ ] `conftest.py` exists and includes required `sys.modules` mocks (Step 5)
- [ ] `make tests` (or targeted `uv run --directory packages/bietlejuice-{pkg} pytest … -v`) passes locally
