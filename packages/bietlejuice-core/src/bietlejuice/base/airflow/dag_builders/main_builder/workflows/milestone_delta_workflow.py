"""DW workflow for milestone dimensions (many strategy SQLs → one Delta table)."""

from __future__ import annotations

from typing import List

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.dw_query_delta_workflow import (
    DwQueryDeltaWorkflow,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class MilestoneDeltaWorkflow(DwQueryDeltaWorkflow):
    """Load milestone dims via shared ``load_milestone_dimension`` Spark job.

    Tables come only from ``tables_customization`` (one load task per target
    table). Strategy files under ``queries/<layer>/<table>/milestones/`` are
    event extractors for that single table — never separate Airflow tables.
    """

    def _get_tables(self) -> List[TableAttributes]:
        custom = self.workflow_args.get("tables_customization") or {}
        tables: List[TableAttributes] = []
        for table_name in sorted(custom.keys()):
            table = TableAttributes(
                self.dag_args, self.workflow_args, LayerEnum.DW, table_name
            )
            tables.append(table)
        if not tables:
            raise ValueError(
                "m=MilestoneDeltaWorkflow._get_tables, "
                "msg=tables_customization must list at least one milestone table"
            )
        return tables
