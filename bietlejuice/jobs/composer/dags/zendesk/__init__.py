from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH

CHATS = "chats"
DEPARTMENTS = "departments"
DEPARTMENTS_WITH_PREFIX = f"{CHATS}_{DEPARTMENTS}"
CHAT_ENGAGEMENTS = "chat_engagements"

SOURCE = "zendesk"
QUERIES_ZENDESK_DATALAKE_PATH = QUERIES_DATALAKE_PATH + SOURCE

DW_SCHEMA = "zendesk"
