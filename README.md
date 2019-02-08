[![Build Status](https://drone.quintoandar.com.br/api/badges/quintoandar/bi-etl-ejuice/status.svg)](http://drone.quintoandar.com.br/quintoandar/bi-etl-ejuice)
![Coverage](https://s3.amazonaws.com/5a-coverage/bi-etl-ejuice/badge-lines.svg)

# Bi-etl-ejuice
<img src="https://cdn.apps.joltteam.com/brikbuild/beetlejuice-pixel-art-8bit-beetlejuice-ghost-pixel-pixel-art-warner-bros-5a24f9adf6c96a8d29720595.brickImg.jpg" width="300" height="300">

Airflow implementation and DAGs.

### Post-clone
#### Git hooks

```
pip install -I flake8==3.5.0 && flake8 --install-hook git && git config --bool flake8.strict true
```

### Configuration Settings

Export `AIRFLOW_GPL_UNIDECODE` variable

```
export AIRFLOW_GPL_UNIDECODE=yes
```

Install `requirements.txt` in a virtualenv:
- To create a virtual environment (inside bi-etl-ejuice directory):
```
virtualenv [ENVIRONMENT_NAME]
```

- To activate a virtual environment:
```
source [ENVIRONMENT_NAME]/bin/activate
```

- Install requirements.txt

```
pip install -r requirements.txt
```

Configure path folder/file which Airflow will run the Dags

- Go to the airflow program folder (probably will be at /home/[YOUR_USERNAME])
- Open file airflow.cfg with an editor
- Edit line with variable `dags_folder`, assigning your right path

### Airflow

Deployment configuration is available within the [terraform](terraform) folder. The new production server is accessible at https://airflow.quintoandar.com.br.

#### Running local Airflow

Initialize the metadata database
```
airflow initdb
```

Start a Airflow webserver instance. Will open Airflow UI on [http://localhost:8080](http://localhost:8080) by default
```
airflow webserver
```

To run the jobs call scheduler
```
airflow scheduler
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
