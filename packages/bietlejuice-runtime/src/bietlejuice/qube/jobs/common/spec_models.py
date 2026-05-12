"""
Pydantic models for YAML spec validation.
Ensures specs are well-formed before execution.
"""

from typing import List, Optional, Union

from pydantic import BaseModel, Field, field_validator


class SourceSpec(BaseModel):
    """
    Source table configuration for dimensions and measures.

    If table and entity_id_col are not specified, they are automatically derived:
    - table: core_{entity}.{entity} (e.g., core.contract, core.visit)
    - entity_id_col: id_{entity} (e.g., id_contract, id_visit)
    """

    table: Optional[str] = Field(
        None, description="Source table name (auto-derived from entity if not provided)"
    )
    entity_id_col: Optional[str] = Field(
        None,
        description="Column name for entity ID (auto-derived from entity if not provided)",
    )
    date_expr: str = Field(..., description="SQL expression to extract event date")
    select: Optional[List[str]] = Field(
        None, description="Columns to select (optimization)"
    )


class LogicSpec(BaseModel):
    """Logic configuration for dimensions."""

    card: Optional[str] = Field(
        "single", description="Cardinality: 'single' or 'multi'"
    )
    type: Optional[str] = Field(
        "string", description="Data type: 'string', 'number', 'boolean'"
    )
    agg: Optional[str] = Field(
        None, description="Aggregation: 'last', 'count', 'sum', etc."
    )
    expr_sql: Optional[str] = Field(
        None, description="Custom SQL expression for aggregation"
    )
    filter_sql: Optional[str] = Field(
        None, description="SQL filter expression (for measures)"
    )
    value_col: Optional[str] = Field(
        None,
        description="Source column to use for dimension value (defaults to dimension name)",
    )

    @field_validator("card")
    @classmethod
    def validate_card(cls, v):
        if v not in ["single", "multi"]:
            raise ValueError(f"card must be 'single' or 'multi', got '{v}'")
        return v

    @field_validator("type")
    @classmethod
    def validate_type(cls, v):
        if v not in ["string", "number", "boolean"]:
            raise ValueError(
                f"type must be 'string', 'number', or 'boolean', got '{v}'"
            )
        return v


class OrderBySpec(BaseModel):
    """Order by configuration for 'last' aggregation."""

    ts_col: str = Field(..., description="Timestamp column for ordering")
    nulls_last: Optional[bool] = Field(True, description="Place nulls last in ordering")


class DefaultsSpec(BaseModel):
    """Default values for missing data."""

    unknown_string: Optional[str] = Field(
        "UNKNOWN", description="Default for missing strings"
    )
    unknown_number: Optional[float] = Field(
        0.0, description="Default for missing numbers"
    )
    unknown_boolean: Optional[bool] = Field(
        False, description="Default for missing booleans"
    )


class DimensionSpec(BaseModel):
    """Complete specification for a dimension."""

    entity: str = Field(..., description="Entity type (e.g., 'visit', 'contract')")
    name: str = Field(..., description="Dimension name")
    windows: Optional[Union[int, List[int]]] = Field(
        [1, 7, 28], description="Time windows in days"
    )
    source: SourceSpec
    logic: LogicSpec
    order_by: Optional[OrderBySpec] = None
    defaults: Optional[DefaultsSpec] = None
    extra_cols: Optional[List[str]] = Field(
        default=[],
        description="Additional columns to include in output (e.g., date columns)",
    )
    include_all_entities: Optional[bool] = Field(
        default=False,
        description="Whether to include all entity IDs (even without data in window)",
    )

    @field_validator("windows")
    @classmethod
    def validate_windows(cls, v):
        if isinstance(v, int):
            if v <= 0:
                raise ValueError(f"window must be positive, got {v}")
            return [v]
        if isinstance(v, list):
            if not v:
                raise ValueError("windows list cannot be empty")
            if any(w <= 0 for w in v):
                raise ValueError(f"all windows must be positive, got {v}")
            return v
        raise ValueError(f"windows must be int or list of ints, got {type(v)}")


class MeasureSpec(BaseModel):
    """Complete specification for a measure."""

    entity: str = Field(..., description="Entity type")
    name: str = Field(..., description="Measure name")
    windows: Optional[Union[int, List[int]]] = Field(
        [1, 7, 28], description="Time windows"
    )
    source: SourceSpec
    logic: LogicSpec

    @field_validator("windows")
    @classmethod
    def validate_windows(cls, v):
        if isinstance(v, int):
            if v <= 0:
                raise ValueError(f"window must be positive, got {v}")
            return [v]
        if isinstance(v, list):
            if not v:
                raise ValueError("windows list cannot be empty")
            if any(w <= 0 for w in v):
                raise ValueError(f"all windows must be positive, got {v}")
            return v
        raise ValueError(f"windows must be int or list of ints, got {type(v)}")

    @field_validator("logic")
    @classmethod
    def validate_logic(cls, v):
        """Ensure measures have filter_sql."""
        if not v.filter_sql:
            raise ValueError("Measures require 'filter_sql' in logic section")
        return v


class MetricDimensionRef(BaseModel):
    """Reference to a dimension in a metric."""

    name: str = Field(..., description="Dimension name")
    card: Optional[str] = Field("single", description="Cardinality")
    type: Optional[str] = Field("string", description="Data type")


class MetricMeasureRef(BaseModel):
    """Reference to a measure in a metric."""

    name: str = Field(..., description="Measure name")


class CountersSpec(BaseModel):
    """Counter configuration for metrics."""

    type: Optional[str] = Field("long", description="Counter type: 'long' or 'approx'")

    @field_validator("type")
    @classmethod
    def validate_type(cls, v):
        if v not in ["long", "approx"]:
            raise ValueError(f"counter type must be 'long' or 'approx', got '{v}'")
        return v


class PrivacySpec(BaseModel):
    """Privacy configuration for k-anonymity."""

    k_anonymity: int = Field(10, description="Minimum group size for k-anonymity", ge=1)


class MetricSpec(BaseModel):
    """Complete specification for a metric."""

    entity: str = Field(..., description="Entity type")
    name: str = Field(..., description="Metric name")
    windows: Optional[Union[int, List[int]]] = Field(
        [1, 7, 28], description="Time windows"
    )
    dimensions: List[MetricDimensionRef] = Field(
        ..., description="Dimensions to slice by"
    )
    measures: List[MetricMeasureRef] = Field(..., description="Measures to aggregate")
    counters: Optional[CountersSpec] = None
    privacy: Optional[PrivacySpec] = None

    @field_validator("windows")
    @classmethod
    def validate_windows(cls, v):
        if isinstance(v, int):
            if v <= 0:
                raise ValueError(f"window must be positive, got {v}")
            return [v]
        if isinstance(v, list):
            if not v:
                raise ValueError("windows list cannot be empty")
            if any(w <= 0 for w in v):
                raise ValueError(f"all windows must be positive, got {v}")
            return v
        raise ValueError(f"windows must be int or list of ints, got {type(v)}")

    @field_validator("dimensions")
    @classmethod
    def validate_dimensions(cls, v):
        if not v:
            raise ValueError("At least one dimension is required")
        return v

    @field_validator("measures")
    @classmethod
    def validate_measures(cls, v):
        if not v:
            raise ValueError("At least one measure is required")
        return v
