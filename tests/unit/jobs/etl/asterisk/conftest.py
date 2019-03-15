from datetime import datetime

import pytest

from bietlejuice.jobs.etl.asterisk import Asterisk, AsteriskCDR, AsteriskCXPanelQueues, AsteriskCXPanelUsers, \
    AsteriskDevices, AsteriskIVRDetails, AsteriskIVREntries, AsteriskQueuesConfig, AsteriskQueuesDetails, AsteriskUsers

S3_BUCKET = 's3-bucket'
EXECUTION_DATE = datetime.today()


@pytest.fixture(scope='session')
def asterisk():
    return Asterisk(S3_BUCKET, EXECUTION_DATE)


@pytest.fixture(scope='session')
def asterisk_cdr():
    return AsteriskCDR(S3_BUCKET, EXECUTION_DATE)


@pytest.fixture(scope='session')
def asterisk_cx_panel_queues():
    return AsteriskCXPanelQueues(S3_BUCKET, EXECUTION_DATE)


@pytest.fixture(scope='session')
def asterisk_cx_panel_users():
    return AsteriskCXPanelUsers(S3_BUCKET, EXECUTION_DATE)


@pytest.fixture(scope='session')
def asterisk_devices():
    return AsteriskDevices(S3_BUCKET, EXECUTION_DATE)


@pytest.fixture(scope='session')
def asterisk_ivr_details():
    return AsteriskIVRDetails(S3_BUCKET, EXECUTION_DATE)


@pytest.fixture(scope='session')
def asterisk_ivr_entries():
    return AsteriskIVREntries(S3_BUCKET, EXECUTION_DATE)


@pytest.fixture(scope='session')
def asterisk_queues_config():
    return AsteriskQueuesConfig(S3_BUCKET, EXECUTION_DATE)


@pytest.fixture(scope='session')
def asterisk_queues_details():
    return AsteriskQueuesDetails(S3_BUCKET, EXECUTION_DATE)


@pytest.fixture(scope='session')
def asterisk_users():
    return AsteriskUsers(S3_BUCKET, EXECUTION_DATE)
