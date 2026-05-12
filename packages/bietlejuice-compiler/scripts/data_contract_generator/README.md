
# Data Contract Generator

This script automates the generation of Data Contract YAML files (following a specific internal schema) for analytical data pipelines. It traverses a standard DAG project structure, extracts metadata from declaration files (`*_declaration.yml`), SQL query locations (`queries/<layer>/*.sql`), and metadata files (`metadata/<layer>/*.yml`), and generates a separate contract for each defined data layer: **raw**, **clean**, **enrich**, and **dw**.

Note: **REVIEW THE OUTPUT AND CORRECT MANUALLY!** There are no guarantees that the contract will have accurate information, since it depends on metadata files that might not have been filled correctly.
## 🚀 Features

  * **Layer-Specific Contracts:** Generates distinct data contracts for the `raw`, `clean`, `enrich`, and `dw` layers.
  * **Metadata Extraction:** Automatically pulls `description`, `owner`, `custom_schema`, and other global DAG metadata.
  * **Table Discovery:** Identifies tables in each layer based on the presence of `.sql` files in the `queries/<layer>` directories.
  * **Extended Metadata:** Extracts table-level `description` and **PII** flags from accompanying `metadata/<layer>/<table_name>.yml` files.
  * **Raw Layer Inference:** Can infer the structure of the `raw` layer contract by tracing the lineage back from the `clean` layer tables when direct `raw` queries are absent.
  * **Environment Templating:** Supports environment-specific paths and catalog names (e.g., `forno`, `prod`).

## ⚙️ Prerequisites

  * Python 3.8+
  * The following Python packages:
      * `pyyaml`

You can install the dependencies using pip:

```bash
pip install pyyaml
```

## 📦 Usage

### 1\. Project Structure

This script assumes your DAG projects follow a structure similar to this:

```
dags/
└── <subdomain>/
    └── <dag_name>/
        ├── <dag_name>_declaration.yml  <- Global DAG metadata
        ├── queries/
        │   ├── clean/
        │   │   └── table_a.sql
        │   └── enrich/
        │       └── table_b.sql
        └── metadata/
            ├── clean/
            │   └── table_a.yml      <- Table description, PII, and lineage
            └── enrich/
                └── table_b.yml
```

### 2\. Running the Script

The script is run from the command line and requires several arguments for configuration.

```bash
python generate_contracts.py --domain <domain> --subdomain <subdomain> --path-dags <dags_root_path> --creator-email <your_email> [OPTIONS]
```

### Command-Line Arguments

| Argument | Type | Default | Required | Description |
| :--- | :--- | :--- | :--- | :--- |
| `--path-dags` | `str` | `dags` | **Yes** | Path to the root DAGs directory OR a single `*_declaration.yml` file. |
| `--creator-email` | `str` | - | **Yes** | Email address of the contract creator (used in `5AMetadata`). |
| `--environment` | `str` | `forno` | No | Target environment (e.g., `forno`, `prod`). Used in IDs and paths. |
| `--output-path` | `str` | `contracts/{environment}/data_contracts` | No | Output directory template for generated YAMLs. |
| `--catalog-name` | `str` | `quintoandar_{environment}` | No | Databricks catalog name template. |
| `--domain` | `str` | - | Yes | Data Domain where the dags belong to |
| `--subdomain` | `str` | - | Yes | Data SubDomain where the dags belong to |


### Example Execution

**To process all DAGs in the lines's folder:**

```bash
python generate_data_contracts.py \
    --path-dags dags/people \
    --environment prod \
    --creator-email "data.engineer@example.com" \
    --domain exampledomain \
    --subdomain examplesubdomain
```

**To process a single DAG declaration file:**

```bash
python generate_data_contracts.py \
    --path-dags dags/subdomain_finance/my_dag/my_dag_declaration.yml \
    --environment forno \
    --creator-email "data.engineer@example.com" \
    --domain exampledomain \
    --subdomain examplesubdomain
```

## 📋 Generated Output

The contracts are generated into a structured directory based on the configuration:

```
contracts/
└── forno/
    └── data_contracts/
        └── <domain>/
            └── <subdomain>/
                └── bietlejuice/
                    └── <dag_name>/
                        ├── <dag_name>_raw.yaml
                        ├── <dag_name>_clean.yaml
                        ├── <dag_name>_enrich.yaml
                        └── <dag_name>_dw.yaml
```
