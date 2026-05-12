# QUBE Jobs

This directory contains the PySpark jobs for building QUBE data layers.

## Quick Reference

See the [main README](../../README.md) for complete documentation.

## Structure

```
qube/jobs/
├── common/              # Shared utilities
│   ├── conf.py         # Configuration management
│   ├── utils.py        # Spark utilities
│   ├── specs_loader.py # Spec validation
│   ├── spec_models.py  # Pydantic models
│   ├── logging_config.py # Logging setup
│   ├── data_quality.py # Quality checks
│   └── privacy.py      # K-anonymity
├── dimensions/         # Dimension builders
│   └── build_dimension.py
├── measures/           # Measure builders
│   └── build_measure.py
└── metrics/            # Metric builders
    └── build_metric.py
```

## Quick Start

### Option 1: Run Complete Pipeline (Recommended)

Use the pipeline script to build everything automatically:

```bash
python scripts/run_pipeline.py
```

This will:
1. Discover all specs
2. Resolve dependencies
3. Build dimensions → measures → metrics in order

### Option 2: Build Individual Components

#### Build a Dimension

```bash
python qube/jobs/dimensions/build_dimension.py \
  --spec qube/specs/dimensions/visit_status.yaml \
  --env dev
```

**Note**: `--date` is optional. If not provided, the job will use the max date from source data.

#### Build a Measure

```bash
python qube/jobs/measures/build_measure.py \
  --spec qube/specs/measures/visit_unique.yaml \
  --env dev
```

#### Build a Metric

```bash
python qube/jobs/metrics/build_metric.py \
  --spec qube/specs/metrics/visit_unique_rent.yaml \
  --env dev
```

**Note**: Metrics automatically infer the date from dimension tables. No `--date` needed.

## Build Order

**Important**: Dependencies must be built in order!

```
1. Dimensions (no dependencies)
       ↓
2. Measures (no dependencies)
       ↓
3. Metrics (requires dimensions + measures)
```

The `run_pipeline.py` script handles this automatically.

## Common Arguments

| Argument | Description | Default | Required |
|----------|-------------|---------|----------|
| `--spec` | Path to YAML spec file | - | ✅ Yes |
| `--date` | Target date (YYYY-MM-DD) | Max in source | ❌ No |
| `--env` | Environment (dev/test/prod) | `dev` | ❌ No |
| `--db-prefix` | Database name prefix | `` | ❌ No |
| `--warehouse` | Warehouse location | From env var | ❌ No |
| `--log-level` | Logging level | `INFO` | ❌ No |
| `--log-format` | Log format (standard/json) | `standard` | ❌ No |

## Spec File Conventions

### Automatic Table and Entity ID Derivation

The jobs automatically derive table names and entity ID columns from the `entity` field:

- **Table**: `core_{entity}.{entity}` (e.g., `core.contract`, `core.visit`, `core.offer`)
- **Entity ID Column**: `id_{entity}` (e.g., `id_contract`, `id_visit`, `id_offer`)

**You don't need to specify these in your specs!**

Example spec (simplified):

```yaml
entity: contract
name: contract_status

source:
  date_expr: "unix_timestamp(ts_updated, \"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'\")"
  select: ["id_contract", "status", "ts_created", "ts_updated"]

logic:
  card: single
  type: string
  agg: last
  value_col: status
```

The job will automatically:
- Use table: `core.contract`
- Use entity_id_col: `id_contract`

### Override (if needed)

If you have non-standard table names, you can still override:

```yaml
source:
  table: custom_schema.custom_table    # Override table
  entity_id_col: custom_id             # Override entity ID column
  date_expr: "..."
```

## Output Tables

### Naming Convention

```
{entity}__{name}__{window}d

Examples:
- contract__contract_status__7d
- visit__visit_total__28d
- offer__offer_dashboard__1d
```

### Database Organization

- **Dimensions**: `qube_dimensions` database
- **Measures**: `qube_measures` database  
- **Metrics**: `qube_metrics` database

With `--db-prefix test_`:
- `test_qube_dim`
- `test_qube_meas`
- `test_qube_met`

## Available Scripts

### Pipeline Runner

```bash
# Build all metrics and dependencies
python scripts/run_pipeline.py

# Build specific metric only
python scripts/run_pipeline.py --metric contract_dashboard

# Dry run (preview what would be built)
python scripts/run_pipeline.py --dry-run
```

### Prerequisites Checker

```bash
# Check if all required tables exist for a metric
python scripts/check_prerequisites.py qube/specs/metrics/visit_unique_rent.yaml --env dev
```

## Troubleshooting

### "Table not found" Error

**Cause**: Trying to build metrics before dimensions/measures exist.

**Solution**: Build in order or use the pipeline script:

```bash
# Use the pipeline script (handles order automatically)
python scripts/run_pipeline.py

# Or build manually in order
python qube/jobs/dimensions/build_dimension.py --spec ...
python qube/jobs/measures/build_measure.py --spec ...
python qube/jobs/metrics/build_metric.py --spec ...
```

### "No data in source" Warning

**Cause**: Source table is empty or date range doesn't overlap.

**Solution**: 
- Check source data exists
- Verify date expression in spec
- Provide explicit `--date` if needed

### K-Anonymity Redacting Everything

**Cause**: All measure counts are below the k threshold.

**Solution**: Lower `k_anonymity` in your metric spec:

```yaml
privacy:
  k_anonymity: 5  # Lower threshold (default is 10)
```

**Note**: With `k_anonymity: 1`, no redaction occurs (since any count ≥ 1 passes).

## See Also

- [Main README](../../README.md) - Complete documentation
- [Notebooks README](../notebooks/README.md) - Databricks notebook version
- [Specs](../specs/) - Example YAML specifications
