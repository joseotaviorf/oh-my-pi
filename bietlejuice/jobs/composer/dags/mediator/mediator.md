  #### Mediator DAG
    This DAG checks for dependencies completion and triggers the dependents DAG in
    the pipeline.
    To force some temporary DAG skipping, use this [variable](/admin/variable/?flt1_0=MEDIATOR_SKIP_LIST)

    Docs:

    - [check-dependencies](https://github.com/quintoandar/airflow-plugins/blob/master/quintoandar_airflow_plugins/dag_mediator_plugin.md) sensor references
    - Mediator [directory](https://drive.google.com/drive/folders/1fIJBKVw4Jjojb9eLu8AHlzmFHBowRRGu) with docs and references