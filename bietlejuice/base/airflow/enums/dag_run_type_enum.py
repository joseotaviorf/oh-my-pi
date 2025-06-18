from enum import Enum


class DagRunTypeEnum(Enum):
    DEFAULT = "default"
    TEST_RUN = "test_run"
    IMPACT_DOWNSTREAM_DEPENDENTS = "impact_downstream_dependents"
    REPROCESSING_RUN = "reprocessing_run"
