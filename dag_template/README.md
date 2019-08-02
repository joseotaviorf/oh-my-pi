## Cookie Cutter for creating an Airflow DAG

Cookie Cutter to ease the creation of new Airflow DAGs (or migration of old ones).

### Usage

Run:
```
cookiecutter dag_template/ -o bietlejuice/jobs/composer/dags/
```

Enter the dag details:

```
dag_name: New Dag
dag_slug: new_dag
description: A New Dag
task_names: dummy1,dummy2
dag_start_date: 2019-01-01
dag_schedule_interval: 0 3 * * *
dag_max_active_runs: 1
dag_catchup: False
```

Generated directory structure:

```
new_dag/
├── __init__.py
├── new_dag.py
└── spark_jobs
    ├── dummy1.py
    ├── dummy2.py
    └── __init__.py
```