# -*- coding: utf-8 -*-
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from scripts.ci_cd.source_layer_validation.read_dag_declaration import (  # noqa: E402
    declaration_path_for_dag_root,
    get_workflow_layer_and_type,
    load_declaration_dict,
)


def test_declaration_path(tmp_path):
    root = tmp_path / "dags/x/my_dag"
    root.mkdir(parents=True)
    assert declaration_path_for_dag_root(root) == root / "my_dag_declaration.yml"


def test_load_and_get_workflow(tmp_path):
    root = tmp_path / "dags/x/wf_dag"
    root.mkdir(parents=True)
    (root / "wf_dag_declaration.yml").write_text(
        "dag:\n  name: wf_dag\nworkflow:\n  type: query_delta\n  layer: dw\n",
        encoding="utf-8",
    )
    data = load_declaration_dict(root)
    assert data["workflow"]["layer"] == "dw"
    layer, wtype = get_workflow_layer_and_type(root)
    assert layer == "dw"
    assert wtype == "query_delta"


def test_missing_declaration(tmp_path):
    root = tmp_path / "dags/x/nope"
    root.mkdir(parents=True)
    assert load_declaration_dict(root) is None
    assert get_workflow_layer_and_type(root) == (None, None)
