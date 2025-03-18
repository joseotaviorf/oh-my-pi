# Local Setup Instructions

## Table of contents

## Table of contents

- [Cloning repository locally](#cloning-repository-locally)
- [Local Airflow environment Astro CLI](#local-airflow-environment-astro-cli)
  - [Install astro cli](#install-astro-cli)
  - [Docker requirements](#docker-requirements)
  - [1. Changing variables value](#1-changing-variables-value)
  - [2. Running Airflow](#2-running-airflow)
    - [2.1 Generate Dag files](#21-generate-dag-files)
    - [2.2 Start the airflow](#22-start-the-airflow)
    - [2.3 Restarting Airflow local environment](#23-restarting-airflow-local-environment)
    - [2.4 Stopping Airflow local environment](#24-stopping-airflow-local-environment)
    - [2.5 Killing Airflow local environment](#25-killing-airflow-local-environment)
  - [3. Deploying local Spark jobs and package](#3-deploying-local-spark-jobs-and-package)
    - [3.1 Uploading local Spark jobs into the cloud](#31-uploading-local-spark-jobs-into-the-cloud)
    - [3.2 Uploading local package into the cloud](#32-uploading-local-package-into-the-cloud)
- [Local Python environment using Pyenv](#local-python-environment-using-pyenv)
  - [Pyenv requirements](#pyenv-requirements)
  - [1. Deploying local Pyenv environment](#1-deploying-local-pyenv-environment)
  - [2. Installing Python requirements](#2-installing-python-requirements)

## Cloning repository locally

```bash
git clone git@github.com:quintoandar/bi-etl-ejuice.git
cd bi-etl-ejuice
```

> **Note:** references to the repo path on the following topics are identified as `{{BIETLEJUICE_PROJECT_PATH}}`

## Local Airflow environment Astro CLI

The Airflow will run in your machine and at Databricks, thereby we can simulate the forno environment.

### Install astro cli

On Mac, run:

```bash
  brew install astro
```

### Docker requirements

- [Colima](https://docs.google.com/document/d/1S1nonH-HBK9-CUX19YczVR2abYchwtGzBDhzclMk7W8/edit?tab=t.0#heading=h.20gk8wb7m9e1)

> **Note:** it's recommended using the QuintoAndar's [local-setup](https://github.com/quintoandar/local-setup) repo.

### 1. Changing variables value

The local Airflow environment require two authentication configs:

- GITHUB_TOKEN: personal token generated for your GitHub user. You may retrieve it in the [GitHub's tokens settings page](https://github.com/settings/tokens).
- DATABRICKS_TOKEN: personal token generated for your Databricks user. Check [this guide](https://docs.databricks.com/dev-tools/api/latest/authentication.html) for more details of how to retrieve it.

Once obtained, both configs may be set as environment variables to be used in the local test enviroment. This step may be done automatically using the Make's recipe `setup-local-variables`.
Type the following line in your command prompt and fill up the configs requested:

```bash
make setup-local-variables
```

> If any of the variables already exist, the recipe **will not** prompt you for a new value, using the existing values instead.
> However, **if any variable is added by you, remember to restart your shell/code editor before continuing!**

### 2. Running Airflow ([Astronomer reference](https://www.astronomer.io/docs/astro/cli/run-airflow-locally/))

**Attention, you should run the following commands in the repository root folder.**

#### 2.1 Generate Dag files
Before running the airflow locally, you might want to generate the dag files for all the dags in the dag builder:

```bash
make create-dag-files
```

Or to generate the dag file for a specific dag, run:

```bash
make create-dag-files dag_name=your_dag_name
```

#### 2.2 Start the airflow:
**-----> Run the repository root folder**

```bash
make run-local-environment
```

Follow the rendering through the Docker container logs. Once it's done, you may access the Airflow webserver GUI on:

`https://localhost:8080`

#### 2.3 Restarting Airflow local environment
**-----> Run the repository root folder**

```bash
make restart-local-environment
```

Restarting your Airflow environment rebuilds your image and restarts the Docker containers running on your local machine with the new image. Restart your environment to apply changes from specific files in your project, or to troubleshoot issues that occur when your project is running.

#### 2.4 Stopping Airflow local environment
**-----> Run the repository root folder**

```bash
make stop-local-environment
```
Airflow connections and task history will be preserved. Use this command when you're finished testing Airflow and you want to stop running its components locally.

#### 2.5 Killing Airflow local environment
**-----> Run the repository root folder**

```bash
make kill-local-environment
```

In most cases, restarting your local project is sufficient for testing and making changes to your project. However, it is sometimes necessary to kill your Docker containers and metadata database for testing purposes. This command (astro dev kill) forces your running containers to stop and deletes all data associated with your local Postgres metadata database, including Airflow connections, logs, and task history.

### 3. Deploying local Spark jobs and package

#### 3.1 Uploading local Spark jobs into the cloud

We configured a new folder at S3 to host spark jobs for each one that will use this infra. That is, the execution will
not get the default folder configured at Forno Composer.

For updating yours spark jobs run the following command:

```bash
make upload-local-spark-jobs
```

#### 3.2 Uploading local package into the cloud

We also configured a new folder at S3 to host it.

For updating the wheel run the following command:

```bash
make upload-local-package
```

## Local Python environment using Pyenv

This setup is only used to run unit tests, linting and style check. To run Airflow, use the [Docker environment](#local-airflow-environment-astro-cli)

### Pyenv requirements

- [pyenv](https://github.com/pyenv/pyenv)
- [pyenv-virtualenv](https://github.com/pyenv/pyenv-virtualenv)

You can install both using pyenv-installer

- [pyenv-installer](https://github.com/pyenv/pyenv-installer)

### 1. Deploying local Pyenv environment

```bash
  make environment
```

> **Note for macOS users**
>
> Pyenv might fail to install Python versions in Mac. As a workaround, you can [download and install versions manually](https://www.python.org/downloads/) or follow the steps provided in [this GitHub issue](https://github.com/pyenv/pyenv/issues/1740#issuecomment-738749988).
>
> Your shell should have automatically activated the `virtualenv`

### 2. Installing Python requirements

```bash
  make requirements
  make requirements-test
  make requirements-lint
```

> **Note For macOS users**
>
> Some dependencies might fail to install on Mac:
>
> - Psycopg2: You can install postgresql via homewbrew and then install psycopg2:
>
>  ```bash
>  brew install postgresql
>  pip install psycopg2
>  ```
>
> - Other dependencies (grpcio, criptography, etc): Make sure you're using a updated version of pip before installing dependencies
>
>  ```bash
>  pip install --upgrade pip
>  ```
