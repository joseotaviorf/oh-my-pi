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
  - [Local Setup](#local-setup)
    - [Clone the project](#1-clone-the-project)
    - [Setup the python environment for the project](#2-setup-the-python-environment-for-the-project)
    - [Install dependencies](#3-install-dependencies)
    - [Set necessary environment variables](#4-set-necessary-environment-variables)
    - [Export AWS credentials](#5-export-aws-credentials)
    - [Set up Airflow](#6-set-up-airflow)
    - [Set up Git hooks](#7-set-necessary-environment-variables)
- [Useful commands](#useful-commands)
- [Improving local Airflow Performance](#improving-local-airflow-performance)
- [Architecture](#architecture)
- [Operators](#operators)
- [Monitoring](#monitoring)
- [Airflow extra features](#airflow-extra-features)
- [Folders structure](#folders-structure)

## Project Overview

We currently have two independent environments in this repo, one for our legacy Airflow that lives on an [EC2](https://airflow.quintoandar.com.br/admin/) and the other for the a managed Airflow on [Google Cloud Platform (GCP)](http://composer.quintoandar.com.br).

The jobs running on the first environment have been implemented with Python 2.6 and run inside the Airflow EC2 (Airflow is the orchestrator and executor at the same time). On the other hand, the second environment defines pipelines implemented with Python 3.6, using Spark to manipulate the data, and letting Airflow only the responsibility of orchestrating them.

The pipelines that currently run on the Airflow EC2 are being migrated and will be discontinued soon. The reason is that Python 2 lost the community support and the limitations to scale the pipelines with parallel processing. The new DAGs should be written according to the new structure (check composer folder). For more information regarding the repo structure look at [Folders Structure](#folders-structure) topic.

## Getting Started
 
 Commands for common steps are defined on a [Makefile](https://en.wikipedia.org/wiki/Makefile) according the python versions 2 and 3 (Ex.: `make environment-python2` and `make environment-python3`). Please refer to the Makefile at the project root to check the existing commands.
 
### Local Setup

**Requirements**

    Python 2.7.16
    [pyenv](https://github.com/pyenv/pyenv)
    [virtualenv](https://virtualenv.pypa.io/en/latest/installation/)

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
export AWS_ACCESS_KEY_ID=<AWS_ACCESS_KEY_ID>
export AWS_SECRET_ACCESS_KEY=<AWS_SECRET_ACCESS_KEY>
export AWS_SESSION_TOKEN=<AWS_SESSION_TOKEN>
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
|-- plugins                        < todo: add short desc. >
|-- scripts                        < todo: add short desc. >
|-- tests                          < todo: add short desc. >
|-- tests3                         < todo: add short desc. >
|-- util                           < todo: add short desc. >
|-- .coveragerc                    < todo: add short desc. >
|-- .dockerignore                  < todo: add short desc. >
|-- .drone.yml                     < todo: add short desc. >
|-- .gitignore                     < todo: add short desc. >
|-- Dockerfile                     < todo: add short desc. >
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
|-- variables.json                 < todo: add short desc. >
```
