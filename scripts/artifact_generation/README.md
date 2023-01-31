# Artifact Generation Scripts

## generate_lineage.py
   This script can be used to generate the YAML metadata files for a DAG. This works better with more simple queries, as clean and dw layers. Enrich may come out very out-of-pattern or even with misleading lineages.

   PS: THIS SCRIPT MUST BE USED "AS IS", ALWAYS CHECK THE RESULTS AND MAKE SURE NOTHING IS WRONG.

   Some use cases:
   1. Generate metadata for all tables on the clean layer DAG "velo" :
      `python scripts/artifact_generation/generate_lineage.py --folder velo`
   2. Generate metadata for all tables on the "dw_random" DAG:
      `python scripts/artifact_generation/generate_lineage.py --folder dw_random`
   3. Generate metadata for ONLY table "foo" on the dw_random DAG:
      `python scripts/artifact_generation/generate_lineage.py --folder dw_random --table foo`
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
