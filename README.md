# Bi-etl-ejuice

Airflow implementation and DAGs.

### Airflow

Deployment configuration is available within the Terraform folder. The new production server is accessible at https://airflow.quintoandar.com.br.

### Architecture

We're trying out an Airflow installation using a LocalExecutor running at a automatically deployed EC2 instance. This architecture is heavily inspired by the [Airflow at WePay presentation](https://www.slideshare.net/criccomini/airflow-at-wepay). Although "simple" (e.g. no Celery, no multiple executor instances, etc.), that seems to be good enough to handle way more load than we'll need anytime soon.

More information on the infrastructure is available at the [terraform](terraform) directory.


### Operators

We're currently migrating old jobs ran by a DockerOperator to the new Airflow architecture, which uses a PythonOperator.

It's recommended that all migrated jobs should use our custom PythonPagerDutyOperator, which triggers a [PagerDuty](https://quintoandar.pagerduty.com/) incident on failure.

```
from jobs.dags.util.python_pd_operator import PythonPagerDutyOperator

PythonPagerDutyOperator(
    dag=dag,
    task_id='validate_schemas',
    provide_context=True,
    python_callable=validate_schemas)
```

### Monitoring

Several tools for monitoring are available for the new Airflow server.

* [Sentry](https://sentry.io/quintoandar-r5/airflow/) will log any errors on the Webserver and Scheduler (errors are reported to the #jobs channel)
* [New Relic APM](https://rpm.newrelic.com/accounts/1585691/applications) monitors transaction times
* [New Relic Synthetics] monitors the Webserver availability (downtime is reported to the #jobs channel)
* Failed jobs will trigger a [PagerDuty](https://quintoandar.pagerduty.com/) incident (reported to the #jobs channel)

Furthermore:

* Webserver, Scheduler and Gunicorn logs are available at [CloudWatch](https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#logs:prefix=/aws/ec2/airflow)
* Jobs logs are available at [S3](https://s3.console.aws.amazon.com/s3/home?region=us-east-1#)
