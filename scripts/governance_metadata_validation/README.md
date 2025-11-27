# Governance Metadata Validation Scripts

## Validate Lineage Consistency
### Description
This script validates that metadata files (lineage) are consistent with their corresponding SQL queries. It ensures that:
1. All columns in the metadata file exist in the SQL query result
2. All columns in the SQL query result are documented in the metadata file
3. Column names match exactly

This validation is critical for CDC pipelines and Delta table merges, as incorrect lineage can cause pipeline failures.

### Usage
The script has three usage modes:
#### All files
Scans all metadata and SQL files in dags directory
```bash
python validate_lineage_consistency.py -a
```

#### Single file
Validates a single file (can be either SQL or metadata file).
```bash
python validate_lineage_consistency.py -f <PATH_TO_FILE>
```

#### Git Diff
Validates all new or modified files according to git diff, from the provided branch to master. If the provided branch is `master`, then it will compare from `HEAD~1` to `HEAD`.
```bash
python validate_lineage_consistency.py -b <BRANCH>
```

### Supported Layers
This validation works for: `raw`, `clean`, `enrich`, `dw`, and `metric` layers.

**Note:** The `core` layer is not supported because Core Models use Spark jobs (Python) instead of SQL queries. Core Models have their own validation: `validate-core-model-schemas`.

### Skip Lists
All validation scripts use a centralized `skip_list.yml` file with three different skip lists:

#### 1. `metadata_files_out_of_pattern` (40 files)
Used by `validate_metadata_files_content.py` to skip metadata files that don't follow the standard schema.

**When to add:** Metadata file has custom structure or is being migrated.

#### 2. `queries_without_metadata_files` (2 files)
Used by `validate_metadata_files_exist.py` to skip SQL queries that intentionally don't have metadata files.

**When to add:** Query is temporary, experimental, or part of a special pipeline.

#### 3. `parsing_skip_list` (9 files)
Used by `validate_lineage_consistency.py` to skip SQL files with advanced Spark SQL features not fully supported by the sqlglot parser.

**Current skip list:** 9 files

**When to add a file to the parsing skip list:**
1. Confirm the SQL is valid and runs correctly in Databricks
2. Add the full path to `parsing_skip_list` in `skip_list.yml`
3. Add a comment explaining why (e.g., "PIVOT clause", "GET_JSON_OBJECT complex function")
4. Test locally with `make validate-lineage-consistency-all`

**What happens:** 
- ⚠️ Files in skip list show a WARNING in CI/CD output but don't fail the pipeline
- 📝 Manual validation is recommended when modifying these files

📖 **Full documentation:** See `LINEAGE_CONSISTENCY_VALIDATION.md` for detailed guide.

---
## Validate Metadata Files Content
### Description
This script validates if one or more metadata files are compliant to the metadata files schema:
#### Raw Layer
Raw layer metadata files must contain the following information: database_name, table_name, owner, domain, description. They may also include a list of columns and the tags associated to those columns.
#### Clean and onwards
Metadata files in layers clean and onwards are similar to raw layer files, but instead of tags must have lineage and documentation for each column. Differently from tags in raw layer files, this information is not optional

### Usage
The script has three usage modes:
#### All files
Scans all metadata files in DAG_PACKAGES_ROOT

```python validate_metadata_files_content.py -a```
#### Single file
Validates a single file.
```python validate_metadata_files_content.py -f <PATH_TO_FILE>```
#### Git Diff
Validates all new or modified files according to git diff, from the provided branch to the current branch (HEAD). If the provided branch is `master`, then it will compare from `HEAD~1` to `HEAD`.
```python validate_metadata_files_content.py -b <BRANCH>```
### Skip List
It is possible to skip the validation for some files by using the `skip_list.yml` file.
To do so, add the file path as a new item in the `metadata_files_out_of_pattern` list.
---
## Validate Metadata Files Exist
### Description
This script validates if one or more SQL query files have a corresponding metadata file. It is used to ensure that all tables have a corresponding metadata file
### Usage
The script has three usage modes:
#### All files
Scans all metadata files in DAG_PACKAGES_ROOT
```python validate_metadata_files_exist.py -a```
#### Single file
Validates a single file.
```python validate_metadata_files_exist.py -f <PATH_TO_FILE>```
#### Git Diff
Validates all new or modified files according to git diff, from the provided branch to the current branch (HEAD). If the provided branch is `master`, then it will compare from `HEAD~1` to `HEAD`.
```python validate_metadata_files_exist.py -b <BRANCH>```
### Skip List
It is possible to skip the validation for some files by using the `skip_list.yml` file.
To do so, add the file path as a new item in the `queries_without_metadata_files` list.
