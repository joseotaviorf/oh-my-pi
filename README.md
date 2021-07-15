<table align="center">
  <tr>
    <th>Build Status</th>
    <th>Coverage</th>
  </tr>
  <tr>
    <td>
        <a href="https://drone.quintoandar.com.br/quintoandar/bi-etl-ejuice">
            <img src="https://drone.quintoandar.com.br/api/badges/quintoandar/bi-etl-ejuice/status.svg" />
        </a>
    </td>
    <td>
        <a href="https://drone.quintoandar.com.br/quintoandar/bi-etl-ejuice">
            <img src="https://s3.amazonaws.com/5a-coverage/bi-etl-ejuice/badge-lines.svg" />
        </a>
    </td>
  </tr>
</table>

# Bi-etl-ejuice
Repository with implementation of Airflow DAGs.

<img src="https://cdn.apps.joltteam.com/brikbuild/beetlejuice-pixel-art-8bit-beetlejuice-ghost-pixel-pixel-art-warner-bros-5a24f9adf6c96a8d29720595.brickImg.jpg" width="300" height="300">

---

## Table of contents

- [Getting Started](#getting-started)
  - [Local Setup python 3 - Docker](#local-setup-python-3---docker)
    - [Clone the project](#1-clone-the-project)
    - [Change variables value](#2-change-variables-value)
    - [Setup docker environment for the project](#3-setup-docker-environment-for-the-project)
    - [Import application variables](#4-import-application-variables)
    - [Restart Airflow](#5-restart-airflow)
    - [Kill Airflow](#6-kill-airflow)
    - [Update your spark jobs in your jobs](#7-update-spark-jobs)
    - [Update python3 wheel in your jobs](#8-update-python3-wheel)
  - [Local Setup python 2 - Docker](#local-setup-python-2---docker)
    - [Clone the project](#1-clone-the-project-1)
    - [Change variables value](#2-change-variables-value-1)
    - [Setup docker environment for the project](#3-setup-docker-environment-for-the-project-1)
    - [Import application variables](#4-import-application-variables-1)
    - [Restart Airflow](#5-restart-airflow-1)
    - [Kill Airflow](#6-kill-airflow-1)
  - [Local Setup python 2 - virtualenv](#local-setup-virtualenv)
    - [Clone the project](#1-clone-the-project-2)
    - [Setup the python environment for the project](#2-setup-the-python-environment-for-the-project)
    - [Install dependencies](#3-install-dependencies)
    - [Set necessary environment variables](#4-set-necessary-environment-variables)
    - [Export AWS credentials](#5-export-aws-credentials)
    - [Set up Airflow](#6-set-up-airflow)
    - [Set up Git hooks](#7-set-necessary-environment-variables)
  - [Local setup python 3 - pyenv](#local-setup-python-3---pyenv)
    - [Clone the project](#1-clone-the-project-3)
    - [Setup python environment](#2-setup-python-environment)
    - [Install dependencies](#3-install-dependencies)
- [Useful commands](#useful-commands)
- [Improving local Airflow Performance](#improving-local-airflow-performance)
- [Architecture](#architecture)
- [Operators](#operators)
- [Monitoring](#monitoring)
- [Airflow extra features](#airflow-extra-features)
- [Folders structure](#folders-structure)

## Project Overview

We currently have two independent environments in this repo, one for our legacy Airflow that lives on an [EC2](https://airflow.quintoandar.com.br/admin/) and the other for the a managed Airflow on [Google Cloud Platform (GCP)](http://composer.quintoandar.com.br).

The jobs running on the first environment have been implemented with Python 2.6 and run inside the Airflow EC2 (Airflow is the orchestrator and executor at the same time). On the other hand, the second environment defines pipelines implemented with Python 3.7, using Spark to manipulate the data, and letting Airflow only the responsibility of orchestrating them.

The pipelines that currently run on the Airflow EC2 are being migrated and will be discontinued soon. The reason is that Python 2 lost the community support and the limitations to scale the pipelines with parallel processing. The new DAGs should be written according to the new structure (check composer folder). For more information regarding the repo structure look at [Folders Structure](#folders-structure) topic.

## Getting Started
 
 Commands for common steps are defined on a [Makefile](https://en.wikipedia.org/wiki/Makefile) according the python versions 2 and 3 (Ex.: `make environment-python2` and `make environment-python3`). Please refer to the Makefile at the project root to check the existing commands.

 Obs: when you're using `python 2 - Docker` and change to `python 3 - Docker` or vice-versa, sometimes the webserver will brake. A quick solution is clear cache from localhost page in your browser.

### Local Setup python 3 - Docker

The Airflow - python3 will run in your machine and at Databricks, thereby we can simulate the forno environment.

**Requirements**
    
    docker (https://docs.docker.com/get-docker/)
    docker-compose (https://docs.docker.com/compose/install/) 

#### 1. Clone the project

    $ git clone git@github.com:quintoandar/bi-etl-ejuice.git
    $ cd bi-etl-ejuice
    
Obs.: From now on the current repo (`bi-etl-ejuice`) will be referred to as $BIETLEJUICE_HOME
    
#### 2. Change variables value
    
Run the following command in the project root folder replacing the placeholders

```bash
    echo export USERNAME=$(whoami) >> ~/.bashrc
    echo export PROJECT_PATH=$(pwd) >> ~/.bashrc
    echo export GITHUB_TOKEN=<GITHUB_TOKEN> >> ~/.bashrc
    echo export DATABRICKS_TOKEN=<DATABRICKS_TOKEN> >> ~/.bashrc
    source ~/.bashrc
```

**Zsh note**: Modify your ~/.zshrc file instead of ~/.bashrc.


- USERNAME: should be the name of your user on your laptop, so you can get it with the command: `whoami`
- PROJECT_PATH: the path to $BIETLEJUICE_HOME.
    Example PROJECT_PATH=/Users/amy/projects/bi-etl-ejuice
- GITHUB_TOKEN: token generated by Github. You can get it [here](https://github.com/settings/tokens).
- DATABRICKS_TOKEN: token generated by Databricks. For more details on how to get it check [this guide]( https://docs.databricks.com/dev-tools/api/latest/authentication.html)

#### 3. Setup docker environment for the project

After install docker and docker-compose, we need to set the local environment

#### 3.1 For macOS users

Docker for Mac requires shared paths to be set explicitly. See [this page](https://docs.docker.com/docker-for-mac) for more info.

You can configure shared paths from Docker -> Preferences -> Resources -> File Sharing. There, add two new paths:

```
/home/PostgreSQL/airflow_py3
/home/your-username/.aws
```

##### 3.2 Create docker local environemnt
```
$ make create-docker-environment-python3
``` 

Waiting some seconds, we could access the airflow UI by: `localhost:8080`


**Important Notes:**
1. Internal QuintoAndar's libs are not included in the local requirements by default, due to dependencies incompatibility. To use them locally for development purposes, include them in `requirements3_local_internal.txt`.
2. Keep in mind that most of internal QuintoAndar's libs are used only in clusters for Spark jobs, not in Airflow's DAGs, so their dependencies are evaluated only at the job execution. To add them to the cluster creation, include their names in the file `requirements3.txt`.

#### 4.Import application variables

In Airflow UI, go to Admin -> Variables, and import variables that you'd like to.

#### 5. Restart Airflow container

Only necessary when some dependencies in requirements.txt changes.

```
$ make restart-docker-environment-python3
``` 

#### 6. Kill Airflow container

Just in case to kill the container instance of Airflow and Postgres. But is not need to use it all time.

```
$ make kill-docker-environment-python3
``` 

#### 7. Update your spark jobs in your jobs

We configured a new folder at S3 to host spark jobs for each one that will use this infra. That is, the execution will
not get the default folder configured at Forno Composer.

For updating yours spark jobs run the following command:

```
$ make upload-local-spark-jobs-to-s3
```

#### 8. Update python3 wheel in your jobs

We also configured a new folder at S3 to host it.

For updating the wheel run the following command:

```
$ make build-local-whl
```

### Local Setup python 2 - Docker

**Requirements**
    
    docker-ce (https://docs.docker.com/install/linux/docker-ce/ubuntu/)
    docker-compose (https://docs.docker.com/compose/install/)

#### 1. Clone the project

    $ git clone git@github.com:quintoandar/bi-etl-ejuice.git
    $ cd bi-etl-ejuice

Obs.: From now on the current repo (`bi-etl-ejuice`) will be referred to as $BIETLEJUICE_HOME

#### 2. Change variables value

Run the following command in the project root folder replacing the placeholders

```bash
    echo export USERNAME=$(whoami) >> ~/.bashrc
    echo export PROJECT_PATH=$(pwd) >> ~/.bashrc
    echo export GITHUB_TOKEN=<GITHUB_TOKEN> >> ~/.bashrc
    source ~/.bashrc
```

**Zsh note**: Modify your ~/.zshrc file instead of ~/.bashrc.

- USERNAME: should be the name of your user on your laptop, so you can get it with the command: `whoami`
- PROJECT_PATH: the path to $BIETLEJUICE_HOME.
    Example PROJECT_PATH=/Users/amy/projects/bi-etl-ejuice
- GITHUB_TOKEN: token generated by Github. You can get it [here](https://github.com/settings/tokens).
#### 3. Setup docker environment for the project

After install docker and docker-compose, we need to set the local environment

##### 3.1 Create docker local environemnt
```
$ make create-docker-environment-python2
``` 

Waiting some seconds, we could access the airflow UI by: `localhost:8080`

#### 4.Import application variables

In Airflow UI, go to Admin -> Variables, and import variables that you'd like to.

#### 5. Restart Airflow container

Only necessary when some dependencies in requirements.txt changes.

```
$ make restart-docker-environment-python2
``` 

#### 6. Kill Airflow container

Just in case to kill the container instance of Airflow and Postgres. But is not need to use it all time.

```
$ make kill-docker-environment-python2
``` 

### Local Setup virtualenv

**Requirements**

    Python 2.7.16
    [pyenv](https://github.com/pyenv/pyenv)
    [virtualenv](https://virtualenv.pypa.io/en/latest/installation.html)

#### 1. Clone the project

    $ git clone git@github.com:quintoandar/bi-etl-ejuice.git
    $ cd bi-etl-ejuice

Obs.: From now on the current repo (`bi-etl-ejuice`) will be referred to as $BIETLEJUICE_HOME

#### 2. Setup the python environment for the project

If you use a Python version >2.7.16, you can follow the steps below to set your system version as 2.7.16. Else, you can go to step 2.2 to set your virtual environment. 

##### 2.1. Setup the virtual environment
```
    $ make environment-python2
```

#### 3. Install dependencies

```
    $ make requirements-python2
```

#### 4. Set necessary environment variables

```    
    $ echo export AIRFLOW_GPL_UNIDECODE=yes >> ~/.bash_profile
    $ echo export AIRFLOW_HOME=~/airflow >> ~/.bash_profile
```

**Zsh note**: Modify your ~/.zshrc file instead of ~/.bash_profile.

#### 5. Export AWS credentials

Go to https://5a.awsapps.com/start#/.
 
Click at __Command line or programmatic access__, copy your credentials and export them.

```
export AWS_SECRET_ACCESS_KEY=$(aws --profile default configure get aws_secret_access_key)
export AWS_ACCESS_KEY_ID=$(aws --profile default configure get aws_access_key_id)
export AWS_SESSION_TOKEN=$(aws --profile default configure get aws_session_token)
```

#### 6. Set up Airflow

##### 6.1 Initialize the metadata database:

    $ airflow initdb

##### 6.2. Open $AIRFLOW_HOME/airflow.cfg and edit dags_folder

    $ dags_folder = $BIETLEJUICE_HOME/bietlejuice/jobs/dags

##### 6.3. Start a Airflow webserver instance. 
Will open Airflow UI on [http://localhost:8080](http://localhost:8080) by default (you will need two terminals).
```
    $ airflow webserver
```
    
To run the jobs call scheduler:
```
    $ airflow scheduler
```

##### 6.4. Export Airflow prod variables and import on you local installation

Exporting:
- Go to https://airflow.quintoandar.com.br/admin/variable/
- Select all
- Click in *With Selected* > *Export*
- Save file on you machine

Obs.: You may need to also export the second page

Importing:
- Go to http://localhost:8080/admin/variable/
- Click in *Chose File* and import you saved file 
- Click *Import Variables*

You need to re-start the webserver. Stop the proccess you started on step 5.3 and re-run:
```
    $ airflow webserver
```
 
##### 6.5. Create a connection variable inside the Airflow UI:

Go to: http://localhost:8080/admin/connection/

Create a new connection like example below:
```
    Conn id: BI_DW
    Conn type: postgres
    Host: <HOST_FORNO>
    Schema: dw
    Login: <LOGIN>   
    Password: <VERY_SECRET_PASSWORD>   
    Port: 5439
```

#### 7. Set up git hooks

```
    $ pip install -I flake8==3.5.0 && flake8 --install-hook git && git config --bool flake8.strict true
```

### Local setup python 3 - pyenv

This setup is only used to run unit-tests, linting and style check. To run Airflow, use the docker environment 

**Requirements**

    [pyenv](https://github.com/pyenv/pyenv)
    [pyenv-virtualenv](https://github.com/pyenv/pyenv-virtualenv)
    # you can install both using pyenv-installer
    [pyenv-installer](https://github.com/pyenv/pyenv-installer)


#### 1. Clone the project

    $ git clone git@github.com:quintoandar/bi-etl-ejuice.git
    $ cd bi-etl-ejuice

Obs.: From now on the current repo (`bi-etl-ejuice`) will be referred to as $BIETLEJUICE_HOME


#### 2. Setup python environment

```
  make environment-python3
```

#### 2.1 For macOS users

Pyenv might fail to install Python versions in Mac. As a workaround, you can [download and install versions manually](https://www.python.org/downloads/) or follow
the steps provided in [this Github issue](https://github.com/pyenv/pyenv/issues/1740#issuecomment-738749988).

Your shell should have automatically activated the virtualenv

#### 3. Install dependencies

```
  make requirements-python3
  make requirements-test-python3
```

#### 3.1 For macOS users

Some dependencies might fail to install on Mac:

* Pandas: Try installing cython and numpy manually: `pip install cython numpy`
  
* Psycopg2: You can install postgresql via homewbrew and then install psycopg2:
  ```
  brew install postgresql
  pip install psycopg2 
  ```
  
* Other dependencies (grpcio, criptography, etc): Make sure you're using a updated version of pip before installing dependencies
  ```
  pip install --upgrade pip
  ```

**Note**: QuintoAndar internal libs might fail to install due to dependency errors. You can avoid installing them by commenting their lines in `requirements3.txt`

Now you should be able to run the commands described in the Useful commands section


### Useful commands

You should be all set with the correct environment. Now you can use any of the following commands:

 - Run all tests and generate project coverage at `/bi-etl-ejuice/htmlcov`:
```
    make unit-tests-python2
```
```
    make unit-tests-python3
``` 
 
 - Run the check style:
```
    make check-style-python3
```

 - Run unit tests using docker environment 
```bash
    make test-environment-python3
```

 - Run specific unit test using docker environment
```bash
    make build-test-environment-python3
    docker run bietlejuice pytest <PATH_TO_TEST_FILE>
```

### Improving local Airflow performance

For best performance, we recommend you to use Postgres as your Airflow database and to change the Airflow executor from SequentialExecutor to LocalExecutor.

1. After installing postgres, create a user, password and database for your Airflow.

2. Open the `airflow.cfg` file and modify the following values:

```
    sql_alchemy_conn = postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@localhost:5432/{DB_SCHEMA}

    executor = LocalExecutor
```

4. Run the command: 
```
    airflow initdb
```

### Architecture

We're trying out an Airflow installation using a LocalExecutor running at a automatically deployed EC2 instance. This architecture is heavily inspired by the [Airflow at WePay presentation](https://www.slideshare.net/criccomini/airflow-at-wepay). Although "simple" (no Celery, no multiple executor instances, etc.), that seems to be good enough to handle way more load than we'll need anytime soon.

More information on the infrastructure is available at the [terraform](terraform) directory.


### Operators

We're currently migrating old jobs ran by a DockerOperator to the new Airflow architecture, which uses a PythonOperator.

It's recommended that all migrated jobs use our custom QuintoAndarPythonOperator, which triggers a [PagerDuty](https://quintoandar.pagerduty.com/) incident on failure.

```
from jobs.dags.util.python_pd_operator import QuintoAndarPythonOperator

QuintoAndarPythonOperator(
    dag=dag,
    task_id='validate_schemas',
    provide_context=True,
    python_callable=validate_schemas)
```

### Monitoring

Several tools for monitoring are available for the new Airflow server.

* [Sentry](https://sentry.io/quintoandar-r5/airflow/) will log any errors on the Webserver and Scheduler (errors are reported to the #jobs channel)
* [New Relic APM](https://rpm.newrelic.com/accounts/1585691/applications) monitors transaction times
* [New Relic Synthetics](https://synthetics.newrelic.com/accounts/1585691/synthetics)  monitors the Webserver availability (downtime is reported to the #jobs channel)
* Failed jobs will trigger a [PagerDuty](https://quintoandar.pagerduty.com/) incident (reported to the #jobs channel)

Furthermore:

* Webserver, Scheduler and Gunicorn logs are available at [CloudWatch](https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#logs:prefix=/aws/ec2/airflow)
* Job logs are available at [S3](https://s3.console.aws.amazon.com/s3/home?region=us-east-1#)

### Airflow extra features

You can enable some extra features like an _Auto Refresh_ button on the DAG's page with [this chrome extension](https://chrome.google.com/webstore/detail/airflow-lifunf/eloabhccocaamibhganmeogabcenidfa)

## Folders structure

```
|-- .terraform                     < todo: add short desc. >
|-- airflow_python2                Airflow configuration for python2
|-- airflow_python3                Airflow configuration for python3
|-- bietlejuice                    < todo: add short desc. >
    |-- db                         < todo: add short desc. > 
        |-- datalake               < todo: add short desc. >             
        |-- dw                     < todo: add short desc. >     
            |-- ddl                < todo: add short desc. >         
            |-- functions          < todo: add short desc. >                 
            |-- queries            < todo: add short desc. >             
            |-- views              < todo: add short desc. >             
        |-- ods                    < todo: add short desc. >     
        |-- skynet                 < todo: add short desc. >         
        |-- source                 < todo: add short desc. >         
    |-- jobs                       < todo: add short desc. >     
        |-- base                   < todo: add short desc. >         
        |-- composer               < todo: add short desc. >             
            |-- base               < todo: add short desc. >             
            |-- consumers          < todo: add short desc. >                 
            |-- dags               < todo: add short desc. >             
            |-- db                 < todo: add short desc. >         
            |-- etl                < todo: add short desc. >         
            |-- loaders            < todo: add short desc. >             
            |-- parsers            < todo: add short desc. >             
            |-- wrappers           < todo: add short desc. >                 
        |-- dags                   < todo: add short desc. >         
        |-- etl                    < todo: add short desc. >     
        |-- old_etl                < todo: add short desc. >         
        |-- sensors                < todo: add short desc. >         
        |-- wrappers               < todo: add short desc. >             
|-- databricks_dag_template        < todo: add short desc. >
|-- docker                         All files to build a container (Airflow and Composer) 
|-- plugins                        < todo: add short desc. >
|-- scripts                        Some scripts used in CI/CD pipelines and docker local
|-- tests                          < todo: add short desc. >
|-- tests3                         < todo: add short desc. >
|-- util                           < todo: add short desc. >
|-- .coveragerc                    < todo: add short desc. >
|-- .dockerignore                  Specify files and folder that should be ignored by the Docker client when generating a build context
|-- .drone.yml                     < todo: add short desc. >
|-- .gitignore                     < todo: add short desc. >
|-- Makefile                       < todo: add short desc. >
|-- MANIFEST.in                    < todo: add short desc. >
|-- README.md                      < todo: add short desc. >
|-- requirements.txt               < todo: add short desc. >
|-- requirements3.txt              < todo: add short desc. >
|-- requirements3_lint.txt         < todo: add short desc. >
|-- requirements3_test.txt         < todo: add short desc. >
|-- requirements_test.txt          < todo: add short desc. >
|-- setup.cfg                      < todo: add short desc. >
|-- setup.py                       < todo: add short desc. >
|-- setup3.cfg                     < todo: add short desc. >
|-- setup3.py                      < todo: add short desc. >
|-- start.sh                       Script to up all Airflow services
|-- variables.json                 < todo: add short desc. >
```
