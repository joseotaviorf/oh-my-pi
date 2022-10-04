# Artifact Generation Scripts

## generate_data_documentation_from_lineage.py

  This script can be used to generate one or many [data-documentation](https://github.com/quintoandar/data-documentation) base yml structure from documented lineages.
  The result will not be a **complete** data-documentation structure, as there are optional tags to be complete, as _joins_with_column_ and _category_, for example.
  Also we do not generate the _categories_ files under `database_name/categories` as this should be optional, but really stimulated.
  Some use cases will be shown here:

  1. Generate for one table:
     `python generate_data_documentation_from_lineage.py --dag_folder "airtable" --table "activated"`
  2. Generate for all tables from one DAG:
     `python generate_data_documentation_from_lineage.py --dag_folder airtable --table "*"`
  3. Generate for all DAGs:
     `python generate_data_documentation_from_lineage.py --dag_folder "*" --table "*"`
  4. Generate for all DAGs on DW layer:
     `python generate_data_documentation_from_lineage.py --dag_folder "dw_*" --table "*"`
