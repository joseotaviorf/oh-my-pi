from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH

# TODO: remove these variables and use job parameters instead.
SOURCE = "cidade_alerta"
QUERIES_CIDADE_ALERTA_DATALAKE_PATH = QUERIES_DATALAKE_PATH + SOURCE
BLOCK_TABLES = [
    "messages",  # system internal table
    "messages.broadcast",  # system internal table
    "messages.routing",  # system internal table
    "scheduling",  # EBDB
    "house",  # EBDB
]
INCREMENTAL_COLUMNS_MAPPING = {"alert": "created_at", "audit": "revision_date"}
INCREMENTAL_TABLES = list(INCREMENTAL_COLUMNS_MAPPING.keys())
