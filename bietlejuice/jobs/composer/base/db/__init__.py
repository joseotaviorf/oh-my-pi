import os

from bietlejuice.jobs.composer.base.db.datalake_metastore_service import (
    DatalakeMetastoreService,
)
from bietlejuice.jobs.composer.base.db.database_enum import (
    DatabaseEnum,
    DatabaseTypeEnum,
)

DIR_PATH = os.path.dirname(os.path.realpath(__file__))

DATALAKE_SQL_DIR = os.path.join(DIR_PATH, "../../db/datalake")

QUERIES_DATALAKE_PATH = DATALAKE_SQL_DIR + "/queries/"
