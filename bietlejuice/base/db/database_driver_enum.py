from enum import Enum


class DatabaseDriverEnum(Enum):
    """
    Mapping of database drivers to each correspondent archtecture
    represented as an Enum object.
    """

    POSTGRES = "org.postgresql.Driver"
    MYSQL = "com.mysql.jdbc.Driver"
    REDSHIFT = "com.amazon.redshift.jdbc42.Driver"
    ORACLE = "oracle.jdbc.driver.OracleDriver"

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]
