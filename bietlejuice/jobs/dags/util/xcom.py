import logging


def xcom_push(task_instance, key):
    k_value = True

    # Executes airflow interdag communication
    logging.info('Creating Xcom: key={} | value={}'.format(key, str(k_value)))
    task_instance.xcom_push(key=key, value=k_value)
