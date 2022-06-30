import yaml
import sys


def get_dependencies_data_from_yaml() -> list:
    """This function will return all data readed in the dependencies yaml file"""

    dependencies_file = "../bietlejuice/jobs/composer/dags/dependencies.yaml"

    with open(dependencies_file, "r") as stream:
        dags = yaml.safe_load(stream)

    return dags


def adjust_dag_name(dag_name: str) -> str:
    """ This function will insert the `:` char in the end of dag_name"""

    if ":" not in dag_name:
        dag_name += ":"

    return dag_name


def find_dependence_dags(dag_name: str, yaml_data, deep=False) -> list:
    """
        This function will find all the DAGs that use the data from the DAG sent by parameter
        Params:
            dag_name: name of the dag to find the dependencies;
            yaml_data: data content of the yaml dependecie file;
            deep: whit this flag will return the dependence of DAG depedences,
                  mapping the all depencies of the main DAG.
    """

    dags = yaml_data
    dependecies_found = set()

    dag_name = adjust_dag_name(dag_name)

    # find the first generation of DAG dependence
    for dag in dags:
        for dependence in dags[dag]:
            if dag_name in dependence:
                dependecies_found.add(f'{dag}')

    # enter in the recursive flow
    if deep:
        dags_to_find = dependecies_found.copy()

        while len(dags_to_find) > 0:
            deep_dependecies_found = find_dependence_dags(dags_to_find.pop(), dags, deep)
            dependecies_found = dependecies_found.union(deep_dependecies_found)

    return dependecies_found


if __name__ == "__main__":

    # get dag name by paramns
    DAG_NAME = sys.argv[1]

    # get deep search flag
    DEEP_SEARCH = False
    if len(sys.argv) > 2 and sys.argv[2].upper() == "DEEP":
        DEEP_SEARCH = True

    depends = find_dependence_dags(
        dag_name=DAG_NAME, yaml_data=get_dependencies_data_from_yaml(), deep=DEEP_SEARCH
    )

    dag_list = open('dag_list.txt', 'w')
    dag_list.writelines(d + '\n' for d in sorted(depends))

    print("Dependency list file created successfully")
