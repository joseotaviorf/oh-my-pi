import logging


def xcom_push(task_instance, key):
    k_value = True

    # Executes airflow interdag communication
    logging.info('Creating Xcom: key={} | value={}'.format(key, str(k_value)))
    task_instance.xcom_push(key=key, value=k_value)


def xcom_pull(task_instance, key, task_id, dag_id, include_prior_dates=True):
    # Executes airflow interdag communication, gathering previous messages
    status = task_instance.xcom_pull(key=key, task_ids=task_id, dag_id=dag_id, include_prior_dates=include_prior_dates)

    logging.info('Getting Xcom: key={} | task_id={} | dag_id={}'.format(key, task_id, dag_id))
    logging.info('Got Xcom: key={} | value={}'.format(key, str(status)))
    return status
