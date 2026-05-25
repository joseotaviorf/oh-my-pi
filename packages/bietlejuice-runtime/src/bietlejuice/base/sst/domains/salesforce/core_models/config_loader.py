import json
from typing import Any, Dict


def table_spec_from_cfg(cfg: Any) -> Dict[str, Any]:
    """
    Load the table specification from the configuration.
    """
    if isinstance(cfg.table_config_json, dict):
        return cfg.table_config_json
    if isinstance(cfg.table_config_json, str):
        return json.loads(cfg.table_config_json)
    raise TypeError(
        f"table_config_json must be dict or str, got {type(cfg.table_config_json)}"
    )
