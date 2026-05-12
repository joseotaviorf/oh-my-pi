"""
YAML spec loader with Pydantic validation.
"""

import json
import os
from typing import Any, Dict

import yaml
from pydantic import ValidationError

from bietlejuice.qube.jobs.common.logging_config import get_logger
from bietlejuice.qube.jobs.common.path_validator import validate_spec_path
from bietlejuice.qube.jobs.common.spec_models import (
    DimensionSpec,
    MeasureSpec,
    MetricSpec,
)

logger = get_logger("specs_loader")


def load_spec_from_json(spec_json: str, validate: bool = True) -> Dict[str, Any]:
    """
    Load and optionally validate a spec from JSON string.

    Args:
        spec_json: JSON string containing spec content
        validate: Whether to validate with Pydantic models

    Returns:
        Parsed spec as dictionary

    Raises:
        ValueError: If JSON parsing fails
        ValidationError: If spec validation fails
    """
    logger.info("Loading spec from JSON string")

    try:
        raw_spec = json.loads(spec_json)
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse JSON: {e}")
        raise ValueError(f"Invalid JSON spec: {e}") from e

    if not raw_spec:
        raise ValueError("Empty spec JSON")

    # Validate with Pydantic if requested
    if validate:
        spec_type = _infer_spec_type("", raw_spec)
        logger.debug(f"Inferred spec type: {spec_type}")

        try:
            if spec_type == "dimension":
                validated = DimensionSpec(**raw_spec)
                logger.info(
                    f"Validated dimension spec: {validated.entity}.{validated.name}"
                )
            elif spec_type == "measure":
                validated = MeasureSpec(**raw_spec)
                logger.info(
                    f"Validated measure spec: {validated.entity}.{validated.name}"
                )
            elif spec_type == "metric":
                validated = MetricSpec(**raw_spec)
                logger.info(
                    f"Validated metric spec: {validated.entity}.{validated.name}"
                )
            else:
                logger.warning("Unknown spec type, skipping validation")
                return raw_spec

            # Return as dict for backward compatibility
            return validated.model_dump()

        except ValidationError as e:
            logger.error("Spec validation failed")
            logger.error(f"Validation errors:\n{e}")
            raise

    return raw_spec


def load_spec(spec_path: str, validate: bool = True) -> Dict[str, Any]:
    """
    Load and optionally validate a YAML spec file.

    Args:
        spec_path: Path to YAML spec file
        validate: Whether to validate with Pydantic models

    Returns:
        Parsed spec as dictionary

    Raises:
        FileNotFoundError: If spec file doesn't exist or path is invalid
        ValidationError: If spec validation fails
        yaml.YAMLError: If YAML parsing fails
        PathSecurityError: If path traversal is detected
    """
    # Security: Validate path to prevent path traversal attacks (CWE-23)
    # Uses dedicated validator with explicit allowlist of base directories
    resolved_path = validate_spec_path(spec_path, must_exist=True)

    logger.info(f"Loading spec from: {resolved_path}")

    try:
        with open(resolved_path) as f:
            raw_spec = yaml.safe_load(f)
    except yaml.YAMLError as e:
        logger.error(f"Failed to parse YAML: {e}")
        raise

    if not raw_spec:
        raise ValueError(f"Empty spec file: {resolved_path}")

    # Validate with Pydantic if requested
    if validate:
        spec_type = _infer_spec_type(str(resolved_path), raw_spec)
        logger.debug(f"Inferred spec type: {spec_type}")

        try:
            if spec_type == "dimension":
                validated = DimensionSpec(**raw_spec)
                logger.info(
                    f"Validated dimension spec: {validated.entity}.{validated.name}"
                )
            elif spec_type == "measure":
                validated = MeasureSpec(**raw_spec)
                logger.info(
                    f"Validated measure spec: {validated.entity}.{validated.name}"
                )
            elif spec_type == "metric":
                validated = MetricSpec(**raw_spec)
                logger.info(
                    f"Validated metric spec: {validated.entity}.{validated.name}"
                )
            else:
                logger.warning(
                    f"Unknown spec type, skipping validation: {resolved_path}"
                )
                return raw_spec

            # Return as dict for backward compatibility
            return validated.model_dump()

        except ValidationError as e:
            logger.error(f"Spec validation failed: {resolved_path}")
            logger.error(f"Validation errors:\n{e}")
            raise

    return raw_spec


def _infer_spec_type(spec_path: str, raw_spec: Dict[str, Any]) -> str:
    """
    Infer spec type from path or content.

    Args:
        spec_path: Path to spec file
        raw_spec: Raw spec dictionary

    Returns:
        Spec type: 'dimension', 'measure', or 'metric'
    """
    # Try to infer from path
    if "/dimensions/" in spec_path or "\\dimensions\\" in spec_path:
        return "dimension"
    if "/measures/" in spec_path or "\\measures\\" in spec_path:
        return "measure"
    if "/metrics/" in spec_path or "\\metrics\\" in spec_path:
        return "metric"

    # Try to infer from content
    if "dimensions" in raw_spec and "measures" in raw_spec:
        return "metric"
    if "logic" in raw_spec:
        logic = raw_spec["logic"]
        if "filter_sql" in logic and "agg" not in logic:
            return "measure"
        return "dimension"

    return "unknown"


def get_spec_path(root: str, layer: str, name: str) -> str:
    """
    Resolves spec path given root, layer, and name.

    Args:
        root: Root directory for specs
        layer: Layer type (dimensions/measures/metrics)
        name: Spec name (with or without .yaml extension)

    Returns:
        Full path to spec file
    """
    if name.endswith(".yaml"):
        return os.path.join(root, layer, name)
    return os.path.join(root, layer, f"{name}.yaml")
