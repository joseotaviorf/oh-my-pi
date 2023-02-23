# Governace Metadata Validation Scripts

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
