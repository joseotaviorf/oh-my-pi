"""
** This module is not used in the project. It is kept here for future reference. **

CurrentStateBuilder is a helper class that builds the current state of an entity from a history of events.
"""

from typing import Dict, List

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.window import Window

from bietlejuice.base.core_models.helpers.event_config_resolution import (
    resolve_event_name,
)


class CurrentStateBuilder:
    """Materialises a wide current-state row from a narrow event history.

    Given a history DataFrame with the fixed schema
    (``id_event``, ``id_{entity}``, ``event_name``, ``value``,
    ``ts_transaction``, ...) this helper:

    1. Identifies entities that changed inside the load window.
    2. For those entities retrieves the **latest** value per
       ``event_name`` across the full history.
    3. Pivots the narrow rows into one wide row per entity with
       correctly typed columns.

    The output is entity-agnostic and can be used by any Core Model
    Spark job that follows the history-first pattern.
    """

    REQUIRED_CONFIG_KEYS = {"target_col", "target_type"}

    @staticmethod
    def build_current_state(
        history_df: DataFrame,
        entity_id_col: str,
        event_configs: List[Dict[str, str]],
        load_start_date: str = None,
        load_end_date: str = None,
    ) -> DataFrame:
        """Build the current-state wide DataFrame from history events.

        Args:
            history_df: Narrow history DataFrame (must contain at least
                ``entity_id_col``, ``event_name``, ``value``,
                ``ts_transaction``).
            entity_id_col: Column holding the entity identifier
                (e.g. ``"id_contract"``).
            event_configs: List of dicts with ``target_col`` and ``target_type``,
                and optional ``event_name`` (defaults to ``ev_{target_col}``).
            load_start_date: Optional inclusive lower bound
                (``ts_transaction`` cast to date).
            load_end_date: Optional inclusive upper bound.

        Returns:
            Wide DataFrame with ``entity_id_col`` plus one column per
            ``target_col``, cast to ``target_type``.
        """
        CurrentStateBuilder._validate_event_configs(event_configs)

        changed_entities = CurrentStateBuilder._find_changed_entities(
            history_df, entity_id_col, load_start_date, load_end_date
        )

        event_names = [
            resolve_event_name(ec, index=i) for i, ec in enumerate(event_configs)
        ]
        latest_df = CurrentStateBuilder._get_latest_values(
            history_df, entity_id_col, changed_entities, event_names
        )

        return CurrentStateBuilder._pivot_and_cast(
            latest_df, entity_id_col, event_configs
        )

    @staticmethod
    def _validate_event_configs(event_configs: List[Dict[str, str]]) -> None:
        if not event_configs:
            raise ValueError("event_configs must not be empty")
        for i, ec in enumerate(event_configs):
            missing = CurrentStateBuilder.REQUIRED_CONFIG_KEYS - set(ec.keys())
            if missing:
                raise ValueError(f"event_configs[{i}] missing required keys: {missing}")
            resolve_event_name(ec, index=i)

    @staticmethod
    def _find_changed_entities(
        history_df: DataFrame,
        entity_id_col: str,
        load_start_date: str,
        load_end_date: str,
    ) -> DataFrame:
        if load_start_date and load_end_date:
            return (
                history_df.filter(
                    (
                        F.col("ts_transaction").cast("date")
                        >= F.lit(load_start_date).cast("date")
                    )
                    & (
                        F.col("ts_transaction").cast("date")
                        <= F.lit(load_end_date).cast("date")
                    )
                )
                .select(entity_id_col)
                .distinct()
            )
        return history_df.select(entity_id_col).distinct()

    @staticmethod
    def _get_latest_values(
        history_df: DataFrame,
        entity_id_col: str,
        changed_entities: DataFrame,
        event_names: List[str],
    ) -> DataFrame:
        filtered = history_df.join(changed_entities, entity_id_col, "inner").filter(
            F.col("event_name").isin(event_names)
        )

        w = Window.partitionBy(entity_id_col, "event_name").orderBy(
            F.col("ts_transaction").desc()
        )
        return (
            filtered.withColumn("_rn", F.row_number().over(w))
            .filter(F.col("_rn") == 1)
            .drop("_rn")
        )

    @staticmethod
    def _pivot_and_cast(
        latest_df: DataFrame,
        entity_id_col: str,
        event_configs: List[Dict[str, str]],
    ) -> DataFrame:
        event_names = [
            resolve_event_name(ec, index=i) for i, ec in enumerate(event_configs)
        ]
        event_map = {
            resolve_event_name(ec, index=i): (ec["target_col"], ec["target_type"])
            for i, ec in enumerate(event_configs)
        }

        pivoted = (
            latest_df.groupBy(entity_id_col)
            .pivot("event_name", event_names)
            .agg(F.first("value"))
        )

        for event_name, (target_col, target_type) in event_map.items():
            if event_name in pivoted.columns:
                pivoted = pivoted.withColumn(
                    target_col,
                    F.col(f"`{event_name}`").cast(target_type),
                )
                if event_name != target_col:
                    pivoted = pivoted.drop(event_name)
            else:
                pivoted = pivoted.withColumn(target_col, F.lit(None).cast(target_type))

        return pivoted
