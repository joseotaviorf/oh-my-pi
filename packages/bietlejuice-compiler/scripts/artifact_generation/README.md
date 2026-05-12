# Artifact Generation Scripts

## generate_metadata.py
   This script can be used to generate the YAML metadata files for a DAG. This works better with more simple queries, as clean and dw layers. Enrich may come out very out-of-pattern or even with misleading lineages. Also will always add the data-documentation keys.

   PS: THIS SCRIPT MUST BE USED "AS IS", ALWAYS CHECK THE RESULTS AND MAKE SURE NOTHING IS WRONG.


   > You can always run `python scripts/artifact_generation/generate_metadata.py -h` to see more details of the parameters.

   Possible parameters:
      --folder, -f : DAG Name folder
      --table, -t : [Optional] Select a specific table to create the metadata
      --owner, -o : [Optional] Pass a owner email to all metadata created
      --no-lineag, -nl : [Optional] Force to ignore lineage and create only data-documentation keys

   Some use cases:
   1. Generate metadata for all tables on the clean layer DAG "velo":
      `python scripts/artifact_generation/generate_metadata.py --folder velo`
   2. Generate metadata for all tables on the clean layer DAG "velo" but don't create lineage keys. Also pass an email to "owner" key:
      `python scripts/artifact_generation/generate_metadata.py --folder velo -nl -o dummy@quintoandar.com.br`
   3. Generate metadata for all tables on the "dw_random" DAG:
      `python scripts/artifact_generation/generate_metadata.py --folder dw_random`
   4. Generate metadata for ONLY table "foo" on the dw_random DAG:
      `python scripts/artifact_generation/generate_metadata.py --folder dw_random --table foo`
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

## generate_enrich_template_from_py_file.py

   This script was created to help with the migration to the DAG Builder. It generates the template for the DAG declaration of enrich DAGs, and fills a few fields
   automatically by using regexes in the Python file and reading the config file. Its automatic filling SHOULD NOT be trusted, and instead verified carefully.

   This is how you use it:
   `python generate_enrich_template_from_py_file.py -d enrich_buyer_prospect`

   It will generate a DAG declaration file in the DAG's folder.