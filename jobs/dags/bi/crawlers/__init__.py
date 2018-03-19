import boto3

STATES = ['sp', 'rj', 'rs', 'sc', 'pr', 'df', 'go', 'mg', 'ba', 'pe', 'ce']


def start_batch_job(job_name, job_queue, job_definition, command=None, vcpus=4, memory=4096):
    batch = boto3.client('batch')

    if command is None or not isinstance(command, list):
        return {'status': 'WRONG_PARAMS', 'jobId': None, 'jobName': None}

    try:
        r = batch.submit_job(
            jobName=job_name,
            jobQueue=job_queue,
            jobDefinition=job_definition,
            containerOverrides={
                'vcpus': vcpus,
                'memory': memory,
                'command': command
            },
            retryStrategy={
                'attempts': 1
            }
        )

        r.update({'status': 'SUBMITTED'})
        return r

    except:
        return {'status': 'ERROR', 'jobId': None, 'jobName': None}
