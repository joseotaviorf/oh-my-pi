from enum import Enum


class CRMTasksTableEnum(Enum):
    CREDIT = 'credit'
    VISIT = 'visit'
    CLOSING = 'closing'
    ONBOARDING_TENANT = 'onboarding_tenant'
    PAYMENT = 'payment'
    INSPECTION = 'inspection'
    LEAD = 'lead'
    PHOTO_JOB = 'photo_job'
