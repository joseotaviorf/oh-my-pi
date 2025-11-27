# Lineage Consistency Validation

## Overview

This script validates that metadata files (lineage) are consistent with their corresponding SQL queries. This validation is **critical** for CDC pipelines and Delta table merge operations. Useful for other layers, like enrich and dw.

## Why is this important?

As confirmed by code analysis:

1. **CDC pipelines depend on lineage** to automatically identify primary keys
2. **If lineage is incorrect**, the pipeline breaks with errors like:
   - "Primary key not found in lineage documentation"
   - Column not found errors during Delta merge
3. **All table columns** must be declared in lineage for proper functioning

## What does the script validate?

✅ All columns in the SQL query exist in the metadata file  
✅ All columns in the metadata exist in the SQL query  
✅ Column names match exactly (case-insensitive)

## Parsing Skip List

**Some SQL files use advanced Spark SQL features that are not fully supported by the sqlglot parser** (databricks dialect). These files are added to the **parsing_skip_list** in `skip_list.yml` to avoid blocking CI/CD while still allowing validation for 99%+ of the codebase.

### Why files are in the skip list:
- **PIVOT clause**: Not fully supported by sqlglot
- **GET_JSON_OBJECT()**: Spark SQL specific function with complex syntax
- **Extremely complex queries**: 1000+ lines with multiple UNION ALL
- **Non-standard SQL syntax**: Edge cases or advanced features

### Current parsing skip list (9 files):
1. `weekly_available_booking_hours.sql` - PIVOT clause
2. `proposal_situation_changes.sql` - GET_JSON_OBJECT() with complex syntax
3. `trino_detractor_queries.sql` - CAST + templates
4. `repressed_demand.sql` - Complex syntax
5. `keywords_from_players.sql` - 1223 lines with multiple UNION ALL
6. `iptu_bh.sql` - String/syntax edge cases
7. `gsc_keyword_region_attributes_bra.sql` - Parsing issues
8. `daily_table_usage_per_user.sql` - Token issues
9. `accounts_payable.sql` - Underscore field names

**Total**: 9 SQL files

### How to add a file to the parsing skip list:

**⚠️ Only add files after confirming the SQL is valid and runs correctly in Databricks!**

1. **Open** `scripts/governance_metadata_validation/skip_list.yml`
2. **Add the file path** to the `parsing_skip_list` section:
   ```yaml
   parsing_skip_list:
     # ... existing files ...
     
     # REASON for skipping (PIVOT, GET_JSON_OBJECT, etc.)
     - dags/domain/dag_name/queries/layer/file.sql
   ```
3. **Add a comment** explaining WHY it's being skipped
4. **Test locally**: `make validate-lineage-consistency-all`
5. **Commit and push**: The file will show as ⚠️ WARNING but won't fail CI/CD

### What happens to files in the parsing skip list:

✅ **CI/CD won't fail** if you modify them  
⚠️ **Warning is shown** in validation output  
📝 **Manual validation strongly recommended** when modifying these files  
✅ **Other files continue to be validated** normally  
📄 **Centralized in skip_list.yml** for easier maintenance

## How to use

### 1. Validate a specific file

```bash
# You can pass either the SQL file or metadata file
make validate-lineage-consistency-all -f dags/domain/dag_name/queries/layer/table.sql
# or
python3 scripts/governance_metadata_validation/validate_lineage_consistency.py -f dags/domain/dag_name/metadata/layer/table.yml
```

### 2. Validate modified files in your branch

```bash
# During local development
PYTHONPATH=. python3 scripts/governance_metadata_validation/validate_lineage_consistency.py -b $(git branch --show-current)

# In CI/CD (automatic)
make validate-lineage-consistency
```

### 3. Validate all project files

```bash
# Useful for audit or migration
make validate-lineage-consistency-all
```

## Output examples

### ✅ Success
```
Validating lineage consistency...
Mode: file

================================================================================
VALIDATION RESULTS
================================================================================

✓ PASSED: 1 file(s)

================================================================================

Result: All metadata files are consistent with their SQL queries! ✓
```

### ❌ Failure
```
Validating lineage consistency...
Mode: file

================================================================================
VALIDATION RESULTS
================================================================================

✗ FAILED: 1 file(s)

  File: dags/domain/dag_name/metadata/layer/table.yml
  SQL:  dags/domain/dag_name/queries/layer/table.sql
    ✗ Columns in SQL query but missing in metadata: ['new_column', 'extra_field']
    ✗ Columns in metadata but missing in SQL query: ['old_column_removed']

================================================================================

Result: Some metadata files are inconsistent with their SQL queries.
Please update the metadata files to match the query columns.
```

## How to fix errors?

### Error: Column in SQL but missing in metadata

**Cause**: You added a column to the query but didn't document it in metadata.

**Solution**: Add the column to the corresponding metadata file:

```yaml
columns:
  new_column:
    description: "Description of the new column"
    lineage:
      - source_database.source_table.source_column
```

### Error: Column in metadata but missing in SQL

**Cause**: The column was removed from the query but is still documented in metadata.

**Solution**: Remove the column from the metadata file or add it back to the SQL query.

## Skip List

To skip validation for specific files, add them to `skip_list.yml`:

```yaml
# Skip metadata validation whenever it makes sense (use it wisely!!!)
metadata_files_out_of_pattern:
  - domain/dag_name/metadata/layer/table.yml

# Skip query-to-metadata validation
queries_without_metadata_files:
  - domain/dag_name/queries/layer/table.sql

# Skip SQL parsing for advanced Spark SQL features
parsing_skip_list:
  - dags/domain/dag_name/queries/layer/complex_query.sql
```

## CI/CD Integration

The script runs automatically in Woodpecker CI/CD for:
- ✅ **ALL branches** (master, forno, feature, hotfix)
- ✅ No exceptions
- ✅ Validates only modified files (not all files)

If validation fails, the PR/commit will be blocked until errors are fixed.

**Important**: Validation runs on all branches, including `hotfix/*`, because these branches go to production and it's critical to ensure lineage consistency to avoid CDC pipeline failures.

## Supported layers

Validation works for the following layers:
- `raw`
- `clean`
- `enrich`
- `dw`
- `metric`

**Note:** The `core` layer is **not supported** because Core Models use Spark jobs (Python) instead of SQL queries. Core Models have their own validation system (`validate-core-model-schemas`).

## Known limitations

1. **Jinja2 templates**: The script replaces Jinja2 variables with dummy values for parsing
2. **Complex SQL**: Very complex queries with nested CTEs may have limited parsing
3. **Case sensitivity**: Comparison is case-insensitive (columns are normalized to lowercase)

## Troubleshooting

### Error: "Error parsing SQL file"
- Check if SQL is valid
- Verify Jinja2 templates are correct
- Try running the script with `-v` (verbose) for more details

### Error: "No columns section found in metadata file"
- Check if metadata file has the `columns:` section
- Confirm that YAML is valid

### Script doesn't find file
- Verify that both SQL and metadata exist
- Confirm they follow the pattern: `queries/layer/table.sql` ↔ `metadata/layer/table.yml`

## More information

- [Main README](README.md)
- [Validation script](validate_lineage_consistency.py)
- [Lineage documentation](../../docs/lineage.md) (if exists)

