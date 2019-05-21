from enum import Enum


class RedshiftStatusEnum(Enum):
    AVAILABLE = 'cluster_available'
    RESTORED = 'cluster_restored'
    SHUTDOWN = 'cluster_deleted'
