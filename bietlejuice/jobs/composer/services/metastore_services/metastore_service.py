from abc import ABC, abstractmethod

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("MetastoreService")


class MetastoreService(ABC):
    """
    Abstract base class for Metastore Services.

    A Metastore is a central repository of meta data. It stores the meta data for tables
    and relations (e.g., schema and location) in a relational database. A Metastore
    Service provides access to this information and allow the manipulation of it.
    """

    @property
    @abstractmethod
    def client(self):
        """
        Returns a DBClient to interact with the Metastore.
        """
        pass

    @logger
    def create_database(self, database_name):
        """
        Creates a database if it doesn't exist.
        :param database_name: database name
        :type database_name: str
        """
        command = f"CREATE DATABASE IF NOT EXISTS {database_name}"
        self.client.run(command)

    @logger
    def repair_table_partitions(self, database_name, table_name):
        """
        Updates partitions and data associated with partitions in a table. It can
        take some time to add(update) all partitions.
        :param database_name: database name
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        """
        command = f"MSCK REPAIR TABLE {database_name}.{table_name}"
        self.client.run(command)

    @logger
    def drop_table(self, database_name, table_name):
        """
        Removes the metadata definition of a table if it exists.
        :param database_name: database name
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        :return:
        """
        command = f"DROP TABLE IF EXISTS `{database_name}`.`{table_name}`"
        self.client.run(command)

    @logger
    def get_table_names(self, database_name, regex="*"):
        """
        Gets the names of tables and views in a database.
        :param database_name: database name
        :type database_name: str
        :param regex: regular expression to filter table and view names. Only the
        wildcard *, which indicates any character, or |, which indicates a choice
        between characters, can be used.
        :type regex: str
        """
        query = f"SHOW TABLES IN {database_name} '{regex}'"
        res = self.client.get_records(query)

        return res

    @logger
    def get_table_description(self, database_name, table_name, formatted=False):
        """
        Gets the description of a table (columns' names and types, including partition
        columns)
        :param database_name: database name
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        :param formatted: ability to get additional metadata info (e.g., location,
        format).
        :type formatted: bool

        :return:
        """
        query = (
            "DESCRIBE " + ("FORMATTED " if formatted else "") + f"{database_name}."
            f"{table_name}"
        )
        res = self.client.get_records(query)

        return res

    @logger
    def add_partitions(self, database_name, table_name, partitions):
        """
        Creates one or more partitions for a table. Each partition consists of
        one or more distinct column name/value combinations.
        :param database_name: database name
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        :param partitions: partitions to add (each one with a unique set of column
        names and values)
        :type partitions: a list of dict where each dict correspond to a single
        partition
        """
        command = f"ALTER TABLE `{database_name}`.`{table_name}` ADD IF NOT EXISTS"
        for partition in partitions:
            part_section = ", ".join(
                [
                    "{} = {}".format(k, v)
                    if not isinstance(v, str)
                    else "{} = '{}'".format(k, v)
                    for k, v in partition.items()
                ]
            )
            command += f"\n PARTITION ( {part_section} )"

        self.client.run(command)

    def create_external_table(
        self,
        database_name,
        table_name,
        table_location,
        table_schema,
        partition_cols,
        format_options,
    ):
        """
        Creates an external table based on underlying data files that exists in
        Amazon S3. When you create an external table, the data referenced must comply
        with the default format or the format that you specify in format_options.
        clauses.
        :param database_name: database name
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        :param table_location: specifies the location of the underlying data,
        for example, 's3://mystorage/'
        :param table_schema: specifies the name and type for each column to be
        created (including partitioning columns).
        :type table_schema: OrderedDict
        :param partition_cols: specifies the names of partition columns in case of
        existence. A table can have one or more partitions, which consist of a
        distinct column name and value combination. A separate data directory is
        created for each specified combination, which can improve query performance
        in some circumstances. Partitioned columns don't exist within the table data
        itself.
        :type partition_cols: list
        :param format_options: specifies the format of the data files,
        serde properties, and tlb properties.
        :type format_options: dict
        """

        # columns builder
        columns_section = ",\n".join(
            [
                "  `" + col + "` " + col_type
                for col, col_type in table_schema.items()
                if not partition_cols or col not in partition_cols
            ]
        )

        # partitions builder
        partitions_section = ""
        if partition_cols:
            partitions_section = "\nPARTITIONED BY (\n  {}\n)".format(
                ",\n  ".join(
                    [" `" + col + "` " + table_schema[col] for col in partition_cols]
                )
            )
        format_section = format_options.get("format", "")
        serde_section = format_options.get("serdeproperties", "")
        tlb_section = format_options.get("tblproperties", "")

        command = (
            f"CREATE EXTERNAL TABLE IF NOT EXISTS `{database_name}`.`{table_name}`\n"
            f"(\n"
            f"{columns_section}\n"
            ")\n"
            f"{partitions_section}\n"
            f"{format_section}\n"
            f"{serde_section}\n"
            f"LOCATION '{table_location}'\n"
            f"{tlb_section};"
        )
        self.client.run(command)
        logger.info(
            f"m=create_external_table, table={database_name}.{table_name}, msg=the "
            f"table was created successfully in the metastore."
        )
