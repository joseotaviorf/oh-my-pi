## Scripts:

- find_dependencies.py:
  This script is able to run localy, and your function is to list all dependencies from a specific DAG or Task.
  Also you can use the param `DEEP` to find all dependencies (the dependencies of dependencies) and discovery the entire impact of your DAG execution.

  To use it you will need only dag_name.

  The script will generate a file with all the dag's dependencies, and can also be used in the "skip_list_generator" script.

  To run, use this command:

  - With deep function:
    `python3 find_dependencies.py <dag_name> deep`

  - Without deep function:
    `python3 find_dependencies.py <dag_name>`

- skip_list_generator.py:
  This script is able to run localy, and your function is to generate generate an updated skip_list with the dags and dates that are passed to it by parameter.

  To use it you will need to create 2 files:

  - skip list.json: a file with the skip_list you want to update (a copy and paste from the airflow variable);
  - dags.txt: a file with the names of the dags you want to add to the skip_list (format: bietlejuice.<dag_name>).

  _File names can be any, but they must be .json and .txt respectively_

  The script necessarily needs 3 parameters:

  - The path of the file skip_list.json that was created;
  - The path where the dags.txt file was created.
  - Last updater is the name of the last person who updated the skip_list file
  - The date is an optional parameter, if not passed it will use the current date.

  To run, use these commands:

  - With date:
    `python3 skip_list_generator.py -j <skip_list_path> -d <dag_list_path> -l <last_updater> -t <date("yyyy-mm-dd")>`

  - Without the date:
    `python3 skip_list_generator.py -j <skip_list_path> -d <dag_list_path> -l <last_updater>`

    _The name of the last updater must be in quotes_

- find_redundant_dependencies.py:
  This script is able to run locally, and its function is to find redundant dependencies in the `dependencies.yaml` file.
  For example, if the DAG "A" is a dependency to "B" and "C", and "B" is also a dependency to "C":

  ```mermaid
       graph LR;
       A-->B;
       A-->C;
       B-->C;
  ```

  "A" should not be a dependency to "C", since "B" already satifies it. This is a problem for mediator, since it will run two times if "A" is triggered during the day: when "A" finishes, and then when "B" finishes. That is a waste of cluster resources, and often causes incidents due to cache.

  This script can print the redundancies to the console, and write them to a CSV file.
  It can analyze a single DAG or all DAGs in the dependencies file.

  To run it, we have three optional parameters:

  (-- dag / -d): full name of the DAG to analyze. If not specified, all DAGs will be checked for redundancies.
  (-- verbosity / -v) how much detail will be printed to console. Goes from 0 (nothing) to 3 (maximum detail).
  (--csv / -c) path to the CSV file which will be written. This CSV will have three columns:

  - DAG: name of the DAG where a redundancy was found
  - Redundant Dependency: name of the dependency that can be removed
  - Satisfied by: a path the satisfies this redundant dependency.

  For example:
  `python3 find_redundant_dependencies.py -d bietlejuice.dw_datamarts_for_sale -v 3 -c redundancies.csv`

  Will check for redundancies in `bietlejuice.dw_datamarts_for_sale`, print them on console with maximum detail, and write to the file redundancies.csv.

  `python3 find_redundant_dependencies.py -v 0 -c redundancies.csv`

  Will check all DAGs for redundancies and write them to redundancies.csv.

- generate_data_documentation_from_lineage.py
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
