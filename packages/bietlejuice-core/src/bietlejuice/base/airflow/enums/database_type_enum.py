from enum import Enum


class DatabaseTypeEnum(Enum):
    POSTGRES = "postgres"
    MONGO = "mongo"
    MYSQL = "mysql"
    ORACLE = "oracle"
    SQLSERVER = "sqlserver"
