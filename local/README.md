# Local Setup Instructions

## Table of contents

- [Cloning repository locally](#cloning-repository-locally)
- [Local Airflow environment using Docker](#local-airflow-environment-using-docker)
  - [Docker requirements](#docker-requirements)
  - [1. Changing variables value](#1-change-variables-value)
  - [4. Deploying Docker local environment](#4-deploying-docker-local-environment)
    - [4.1 Running Airflow in Docker local environment](#4.1-running-airflow-in-docker-local-environment)
    - [4.2 Restarting Airflow local environment](#4.2-restarting-airflow-local-environment)
    - [4.3 Stopping Airflow local environment](#4.3-stopping-airflow-local-environment)
  - [3. Deploying local Spark jobs and package](#3-deploying-local-spark-jobs-and-package)
    - [3.1 Uploading local Spark jobs into the cloud](#3.1-uploading-local-spark-jobs-into-the-cloud)
    - [3.2 Uploading local package into the cloud](#3.2-uploading-local-package-into-the-cloud)
- [Local Python environment using Pyenv](#local-python-environment-using-pyenv)
  - [Pyenv requirements](#pyenv-requirements)
  - [1. Deploying local Pyenv environment](#1-deploying-local-pyenv-environment)
  - [2. Installing Python requirements](#2-installing-python-requirements)

## Cloning repository locally

```bash
git clone git@github.com:quintoandar/bi-etl-ejuice.git
cd bi-etl-ejuice
```

> **Note:** references to the repo path on the following topics are identified as {{BIETLEJUICE_PROJECT_PATH}}

## Local Airflow environment using Docker

The Airflow will run in your machine and at Databricks, thereby we can simulate the forno environment.

### Docker requirements

- [docker](https://docs.docker.com/get-docker/)
- [docker-compose](https://docs.docker.com/compose/install/)

> **Note:** it's recommended using the QuintoAndar's [local-setup](https://github.com/quintoandar/local-setup) repo.

### 1. Changing variables value

Run the following command in the project root folder, replacing the placeholders

> **Note for macOS ZSH users**: Replace `~/.bashrc` by `~/.zshrc` in the code to modify the proper file.

```bash
echo export USERNAME=$(whoami) >> ~/.bashrc
echo export PROJECT_PATH=$(pwd) >> ~/.bashrc
echo export GITHUB_TOKEN=<GITHUB_TOKEN> >> ~/.bashrc
echo export DATABRICKS_TOKEN=<DATABRICKS_TOKEN> >> ~/.bashrc
source ~/.bashrc
```

- USERNAME: name of your current user on your work station, retrievable by the command `whoami`.
- PROJECT_PATH: full path to the {{BIETLEJUICE_PROJECT_PATH}} repository folder. Once it's your current folder, it's retrievable by the command `pwd`.
    Example `PROJECT_PATH=/Users/amy/projects/bi-etl-ejuice`
- GITHUB_TOKEN: personal token generated for your GitHub user. You may retrieve it in the [GitHub's tokens settings page](https://github.com/settings/tokens).
- DATABRICKS_TOKEN: personal token generated for your Databricks user. Check [this guide](https://docs.databricks.com/dev-tools/api/latest/authentication.html) for more details of how to retrieve it.

### 2. Deploying Docker local environment

Local environment deploys 4 services using `docker-compose`:

- Airflow webserver
- Airflow worker
- Redis
- Postgres

> For macOS users
>
> We use volumes inside `docker-compose` containers to allow reflecting file changes onto the Docker environment. In order to enable acccess to local folders - so Docker sets them as volumes -, Docker for Mac uses "shared paths", where folders paths are added explicitly to be allowed as Docker volumes (check [this page](https://docs.docker.com/docker-for-mac) for more info).
> You may configure shared paths in `Docker -> Preferences -> Resources -> File Sharing`.
>
> Add the following path into your shared paths settings:
>
> - `{{BIETLEJUICE_PROJECT_PATH}}/bietlejuice/dags`
> - `/tmp/PostgreSQL/airflow`

#### 2.1 Running Airflow in Docker local environment

```bash
make run-local-environment
```

The Airflow launch process may take a while, as all DAGs must be rendered by Airflow inside the Docker container twice: once for the database creation - which occurs at the continar startup - and once for the Airflow webserver startup after the database creation, when the Airflow DAG Bag is updated.
Follow the rendering through the Docker container logs. Once it's done, you may access the Airflow webserver GUI on:

`https://localhost:8080`

#### 2.2 Restarting Airflow local environment

```bash
make restart-local-environment
```

Usually the `docker-compose` containers might have to be restarted due to memory outage when reading DAGs, or when changes are made in any `requirements` file.

#### 2.3 Stopping Airflow local environment

```bash
make stop-local-environment
```

Shuts down Airflow's local environment, killing Docker containers, including Airflow webserver, workers, Postgres backend service and Redis queue service.
All Airflow backend data is kept locally in the path `/tmp/PostgreSQL/airflow`, so **all DAG runs, connections and variables are persisted and retrieved when the environment is started again.**

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

This setup is only used to run unit tests, linting and style check. To run Airflow, use the [Docker environment](#local-airflow-environment-using-docker)

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
