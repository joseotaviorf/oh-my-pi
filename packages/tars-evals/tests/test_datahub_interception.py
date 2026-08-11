import asyncio
import json
from pathlib import Path

from tars_evals.tools import run_bash


def _script(tmp_path: Path) -> Path:
    skill_dir = tmp_path / "tars"
    (skill_dir / "scripts").mkdir(parents=True)
    return skill_dir


def test_intercepts_search_query(tmp_path):
    skill_dir = _script(tmp_path)
    dh = skill_dir / "scripts" / "datahub_connect.py"
    q = '{ searchAcrossEntities(input:{query:"chatbot",types:[DATA_PRODUCT],count:5}){ total } }'
    cmd = f"python3 {dh} gql '{q}' 2>&1"

    async def _run():
        return await run_bash(skill_dir)(command=cmd)

    payload = json.loads(asyncio.run(_run()))
    assert payload["data"]["searchAcrossEntities"]["total"] >= 1


def test_intercepts_probe(tmp_path):
    skill_dir = _script(tmp_path)
    dh = skill_dir / "scripts" / "datahub_connect.py"

    async def _run():
        return await run_bash(skill_dir)(command=f"python3 {dh} probe")

    payload = json.loads(asyncio.run(_run()))
    assert payload.get("probe_ok") is True


def test_datahub_never_spawns_subprocess(tmp_path):
    # datahub_connect.py need not exist on disk — like the trino mock.
    skill_dir = _script(tmp_path)
    dh = skill_dir / "scripts" / "datahub_connect.py"
    assert not dh.exists()
    q = '{ searchAcrossEntities(input:{query:"offboarding",types:[DATA_PRODUCT],count:5}){ total } }'

    async def _run():
        return await run_bash(skill_dir)(command=f"python3 {dh} gql '{q}'")

    payload = json.loads(asyncio.run(_run()))
    assert "data" in payload


def test_intercepts_python_dash_c_form(tmp_path):
    # tars's `python3 -c "<body>"` discovery snippet: the interceptor
    # regex-extracts the query from the body (never exec'd). The query's inner
    # double quotes force a triple-quote wrapper in the body (a single "
    # wrapper would terminate the _GQL_CALL_RE backreference early).
    skill_dir = _script(tmp_path)
    q = '{ searchAcrossEntities(input:{query:"chatbot",types:[DATA_PRODUCT],count:5}){ total } }'
    body = f'from datahub_connect import gql; result = gql("""{q}""", {{}})'
    cmd = f"python3 -c '{body}'"

    async def _run():
        return await run_bash(skill_dir)(command=cmd)

    payload = json.loads(asyncio.run(_run()))
    assert "data" in payload
