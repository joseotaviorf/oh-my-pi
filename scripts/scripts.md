## Scripts:

    > find_dependencies.py:
        This script is able to run localy, and your function is to list all dependencies from a specific DAG or Task.
        Also you can use the param `DEEP` to find all dependencies (the dependencies of dependencies) and discovery the entire impact of your DAG execution.

        To use it you will need only dag_name.

        The script will generate a file with all the dag's dependencies, and can also be used in the "skip_list_generator" script.

        To run, use this command:

            - With deep function: 
                python3 find_dependencies.py <dag_name> deep
            
            - Without deep function:
                python3 find_dependencies.py <dag_name>

    > skip_list_generator.py:
        This script is able to run localy, and your function is to generate generate an updated skip_list with the dags and dates that are passed to it by parameter. 

        To use it you will need to create 2 files: 
            - skip list.json: a file with the skip_list you want to update (a copy and paste from the airflow variable);
            - dags.txt: a file with the names of the dags you want to add to the skip_list (format: bietlejuice.<dag_name>).

        *File names can be any, but they must be .json and .txt respectively*

        The script necessarily needs 3 parameters: 
            - The path of the file skip_list.json that was created; 
            - The path where the dags.txt file was created.
            - Last updater is the name of the last person who updated the skip_list file
            - The date is an optional parameter, if not passed it will use the current date.

        To run, use these commands:
            - With date:
                python3 skip_list_generator.py -j <skip_list_path> -d <dag_list_path> -l <last_updater> -t <date("yyyy-mm-dd")>
            
            - Without the date:
                python3 skip_list_generator.py -j <skip_list_path> -d <dag_list_path> -l <last_updater>
            
            *The name of the last updater must be in quotes*
