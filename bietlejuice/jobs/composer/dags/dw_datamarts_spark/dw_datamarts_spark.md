## DW Datamarts Spark
​
### Overview

This folder has a DAG factory that dinamically creates datamart DAGs based on a configuration file. Each context has its own documentation with the name `<context>/<context>.md`.

### Creating a new DAG Context

To create a new context, its configuration must be added to `dw_datamarts_spark_forno_conf.yml` and `dw_datamarts_spark_prod_conf.yml`.

Inside `dags`, each key represents a different context, which can have two configurations:
 - `cluster_name`: name of the Airflow variable with the cluster configurations. This parameter is optional, and will be set to `databricks_default_cluster` if omitted.
 - `owner`: this parameter is mandatory. It is the name of the team responsible for the DAG.

 After updating the configs, create a folder with the name of the context. Inside, a documentation file has to be created for that context, with the name `<context>.md`. In there, you will also create `<context>.yml`, a configuration file for the datamarts in the DAG.

 This configuration is set like this:

 ```
   <tree_path>: # Query will be located in db/datalake/queries/dw_datamarts_spark/dw/<tree_path>/<datamart-name>.sql. This is useful, for example, for the DAG dw_datamarts_growth_dep_manual_costs.
     <datamart_name>:
       depends_on: # This is optional, only necessary for datamarts with inner dependencies
         - <datamart_dependency_name>
         - <datamart_2_dependency_name> 
     <datamart_name>: {} # If your datamart has no inner dependencies, just declare it with an empty object
```

### Creating a new Datamart

Once the context already exists, in order to run a new datamart, please follow these steps:

1. Create Spark SQL query on `bietlejuice/jobs/composer/db/datalake/queries/dw_datamarts_spark/dw/<context>/<datamart-name>.sql`.
2. Create lineage on `bietlejuice/jobs/composer/db/datalake/metadata/dw_datamarts_spark/dw/<context>/<datamart-name>.yml`.
3. Add datamart configuration to `bietlejuice/jobs/composer/dags/dw_datamarts_spark/<context>/<context>.yml`. There, you can set the subfolder the query is located under `dw_datamarts_spark` using `tree_path`. Also, inner dependencies can be set using `depends_on`, exactly like the previous version of the DAG.
4. Make sure all of its external dependencies are specified in `bietlejuice/jobs/composer/dags/dependencies.yaml`
5. Test the query thoroughly in Production Databricks and the DAG execution in forno.

For more detailed information about creating Datamarts, please access the Notion page [Criação de Datamarts](https://www.notion.so/productquintoandar/Cria-o-de-Datamarts-8b889796c76146ebbac27f4819695146).

For more information about the Datamart Migration from Athena and Redshift, please access [this page](https://www.notion.so/productquintoandar/Datamarts-Migration-0d04a6d55e7846479174f14462f2bbef).

### Technical Disclaimers

Contrary to the previous version, the DAGs generated here run datamarts exclusively on Spark SQL. They are also the first DW DAGs that will not copy their contents into Redshift. The DAGs will be named `dw_datamarts_spark.<context>`, and the datamarts will be available on Databricks and Trino on the schema `dw_datamarts`.
