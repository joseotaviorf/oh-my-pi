import textwrap
from datetime import datetime


from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.db.database_driver_enum import DatabaseDriverEnum
from bietlejuice.consumers.db_consumers.db_consumer import DBConsumer

logger = QuintoAndarLogger("SQLServerConsumer")


class SQLServerConsumer(DBConsumer):
    """
    Consumer para buscar dados de um banco SQL Server via Spark,
    retornando-os como um DataFrame do Spark.
    """

    def __init__(self, conn_config: dict, spark_client, fetch_size=50000):
        """
        Inicializa o consumer com a configuração da conexão e o cliente Spark.

        :param conn_config: Dicionário com informações da conexão (host, porta, usuário, etc.).
        :param spark_client: Cliente Spark para executar queries.
        :param fetch_size: Número de registros buscados por vez na consulta (padrão: 50000).
        """
        driver_enum = DatabaseDriverEnum[conn_config["dbtype"].upper()]

        self.conn_config = conn_config
        self.spark_client = spark_client

        self.spark_common_options = {
            "driver": driver_enum.value,
            "url": f"jdbc:sqlserver://{conn_config['host']}:{conn_config['port']};databaseName={conn_config['db']};encrypt=false",
            "user": conn_config["user"],
            "password": conn_config["pwd"],
            "fetchsize": fetch_size,
        }

    @logger
    def get_data_from_query(self, query: str):
        """
        Executa uma query no SQL Server e retorna os resultados como um DataFrame do Spark.

        :param query: Query SQL a ser executada.
        :return: DataFrame com os resultados da consulta.
        """
        logger.info(f"Executando query: {query}")
        return self.spark_client.get_data_from_external_source(
            format="jdbc", options={**self.spark_common_options, "query": query}
        )

    @logger
    def get_data_from_table(self, table_name: str):
        """
        Busca todos os dados de uma tabela, excluindo campos específicos se necessário.

        :param table_name: Nome da tabela a ser consultada.
        :return: DataFrame com os dados da tabela.
        """
        logger.info(f"Buscando dados da tabela: {table_name}")

        return self.spark_client.get_data_from_external_source(
            format="jdbc", options={**self.spark_common_options, "dbtable": table_name}
        )

    @logger
    def get_table_names_and_sizes(self, table_name: str):
        """
        Retorna o nome e tamanho de uma tabela no SQL Server.

        :param table_name: Nome da tabela para consulta.
        :return: DataFrame contendo nome e tamanho da tabela.
        """
        query = textwrap.dedent(
            f"""
            SELECT t.name AS TABLE_NAME, SUM(a.total_pages) * 8.0 / 1024 AS size_mb
            FROM sys.tables t
            JOIN sys.indexes i ON t.object_id = i.object_id
            JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
            JOIN sys.allocation_units a ON p.partition_id = a.container_id
            WHERE t.name = '{table_name}'
            GROUP BY t.name
        """
        )
        return self.get_data_from_query(query)

    @logger
    def get_data_from_table_in_parallel(self, *args, **kwargs):
        raise NotImplementedError(
            "get_data_from_table_in_parallel ainda não foi implementado."
        )

    @logger
    def get_table_schema(self, table_name: str):
        """
        Retorna o esquema de uma tabela no SQL Server.

        :param table_name: Nome da tabela.
        :return: DataFrame contendo as colunas e seus tipos de dados.
        """
        query = textwrap.dedent(
            f"""
            SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH,
                   NUMERIC_PRECISION, NUMERIC_SCALE, IS_NULLABLE
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_NAME = '{table_name}'
        """
        )
        return self.get_data_from_query(query)

    @logger
    def get_table_primary_keys(self, table_name: str):
        """
        Retorna as chaves primárias de uma tabela.

        :param table_name: Nome da tabela.
        :return: DataFrame contendo os nomes das colunas que são chaves primárias.
        """
        query = textwrap.dedent(
            f"""
            SELECT c.COLUMN_NAME
            FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE c
            JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS t
            ON c.CONSTRAINT_NAME = t.CONSTRAINT_NAME
              AND c.TABLE_SCHEMA = t.TABLE_SCHEMA
            WHERE t.CONSTRAINT_TYPE = 'PRIMARY KEY'
            AND t.TABLE_NAME = '{table_name}'
        """
        )
        return self.get_data_from_query(query)

    @logger
    def get_incremental_data_from_table(
        self,
        table_name: str,
        date_filter_columns: list,
        start_interval: str,
        end_interval: str,
    ):
        """
        Retorna dados incrementais de uma tabela baseados em um intervalo de datas.

        :param table_name: Nome da tabela.
        :param date_filter_columns: Lista de colunas de data para filtragem.
        :param start_interval: Data de início no formato "YYYY-MM-DD".
        :param end_interval: Data de fim no formato "YYYY-MM-DD".
        :return: DataFrame com os dados filtrados.
        """
        start_range_date = datetime.strptime(start_interval, "%Y-%m-%d").isoformat()
        end_range_date = datetime.strptime(
            end_interval + " 23:59:59", "%Y-%m-%d %H:%M:%S"
        ).isoformat()

        fields_filter = " AND ".join(
            [
                f"{col} BETWEEN '{start_range_date}' AND '{end_range_date}'"
                for col in date_filter_columns
            ]
        )

        query = f"SELECT * FROM {table_name} WHERE {fields_filter}"
        return self.get_data_from_query(query)
