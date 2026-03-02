from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import (
    col,
    current_timestamp,
    last,
    lit,
    max as spark_max,
    regexp_replace,
    when,
)

from dags.core.core_brokers.spark_jobs.core_brokers_base import (
    CoreBrokersBaseSparkJob,
)
from bietlejuice.base.core_models.helpers.historical_helper import HistoricalHelper

HISTORICAL_TABLE = "brokers_historical"


class CoreBrokersSparkJob(CoreBrokersBaseSparkJob):
    """Core Brokers Spark job implementation.

    Consolidates broker partner data from the 3P Partners operation,
    joining company, address, document and product information into
    a single denormalized view of each broker.

    Supports two output tables:
      - ``brokers`` (current state from clean layer)
      - ``brokers_historical`` (all CDC transactions from transactional layer)
    """

    def get_brokers_config(self):
        """Get broker-specific configuration from forno_conf/prod_conf."""
        return {
            "ENTITY_TYPE": self.get_config("ENTITY_TYPE"),
            "COMPANY_TABLE": self.get_config("COMPANY_TABLE"),
            "COMPANY_ADDRESS_TABLE": self.get_config("COMPANY_ADDRESS_TABLE"),
            "COMPANY_DOCUMENT_TABLE": self.get_config("COMPANY_DOCUMENT_TABLE"),
            "DOCUMENT_TABLE": self.get_config("DOCUMENT_TABLE"),
            "COMPANY_PRODUCT_TABLE": self.get_config("COMPANY_PRODUCT_TABLE"),
            "ADDRESS_TABLE": self.get_config("ADDRESS_TABLE"),
        }

    # ── create_core_model dispatch ──────────────────────────────────

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        """Dispatch to the appropriate model builder based on table_name."""
        if args.table_name == HISTORICAL_TABLE:
            return self._create_historical_model(spark, args)
        return self._create_current_state_model(spark, args)

    # ── current-state model (brokers) ───────────────────────────────

    def _create_current_state_model(self, spark: SparkSession, args) -> DataFrame:
        """Create the current-state brokers model from clean layer data."""

        config = self.get_brokers_config()

        company_df = self._load_data(
            spark, config["COMPANY_TABLE"], args, apply_date_filter=True
        )
        company_address_df = self._load_data(
            spark, config["COMPANY_ADDRESS_TABLE"], args
        )
        company_document_df = self._load_data(
            spark, config["COMPANY_DOCUMENT_TABLE"], args
        )
        document_df = self._load_data(spark, config["DOCUMENT_TABLE"], args)
        company_product_df = self._load_data(
            spark, config["COMPANY_PRODUCT_TABLE"], args
        )
        address_df = self._load_data(spark, config["ADDRESS_TABLE"], args)

        result_df = self._transform_and_join(
            company_df,
            company_address_df,
            company_document_df,
            document_df,
            company_product_df,
            address_df,
        )

        result_df = self._select_final_columns(result_df)
        return self._add_partition_columns(result_df, "ts_updated")

    # ── historical model (brokers_historical) ───────────────────────

    def _create_historical_model(self, spark: SparkSession, args) -> DataFrame:
        """Create the historical brokers model from transactional + clean data.

        Company transactions come from the transactional layer (every insert,
        update, delete). Related entities (address, document, product) are
        joined from the clean layer to provide the latest context for each
        transaction.
        """
        config = self.get_brokers_config()

        transactional_table = self.get_config("COMPANY_TRANSACTIONAL_TABLE")
        company_df = HistoricalHelper.load_transactional_data(
            spark,
            transactional_table,
            args,
        )

        company_address_df = self._load_data(
            spark, config["COMPANY_ADDRESS_TABLE"], args
        )
        company_document_df = self._load_data(
            spark, config["COMPANY_DOCUMENT_TABLE"], args
        )
        document_df = self._load_data(spark, config["DOCUMENT_TABLE"], args)
        company_product_df = self._load_data(
            spark, config["COMPANY_PRODUCT_TABLE"], args
        )
        address_df = self._load_data(spark, config["ADDRESS_TABLE"], args)

        result_df = self._transform_and_join(
            company_df,
            company_address_df,
            company_document_df,
            document_df,
            company_product_df,
            address_df,
        )

        cdc_cols = HistoricalHelper.select_cdc_columns(company_df, "c")
        result_df = self._select_final_columns(result_df, extra_columns=cdc_cols)
        result_df = self._add_is_current(result_df, "sk_broker")
        return self._add_partition_columns(result_df, "ts_database_transaction")

    # ── shared transformation logic ─────────────────────────────────

    def _transform_and_join(
        self,
        company_df,
        company_address_df,
        company_document_df,
        document_df,
        company_product_df,
        address_df,
    ) -> DataFrame:
        """Process sub-entities and join everything onto the company spine."""
        company_address_processed = self._process_company_address(company_address_df)
        company_document_processed = self._process_company_document(
            company_document_df, document_df
        )
        company_product_processed = self._process_company_product(company_product_df)

        return self._join_all_data(
            company_df,
            company_address_processed,
            company_document_processed,
            company_product_processed,
            address_df,
        )

    def _process_company_address(self, company_address_df):
        """Get the last address per company."""
        return company_address_df.groupBy("id_company").agg(
            last("id_address").alias("id_address")
        )

    @staticmethod
    def _extract_document_number(doc_type, alias_name):
        """Build an aggregate expression that extracts a cleaned document number.

        Returns a ``Column`` expression suitable for use inside ``.agg()``.
        """
        cleaned = regexp_replace(col("d.identification_number"), "[^0-9]", "")
        agg_expr = spark_max(when(col("d.document_type") == doc_type, cleaned))
        return when(agg_expr != "", agg_expr).alias(alias_name)

    def _process_company_document(self, company_document_df, document_df):
        """Pivot document types to extract CRECI, CNPJ, and RFC per company."""
        cd_with_doc = company_document_df.alias("cd").join(
            document_df.alias("d").filter(col("status") == "ACTIVE"),
            col("cd.id_document") == col("d.id"),
            "left",
        )

        return (
            cd_with_doc.groupBy("cd.id_company")
            .agg(
                self._extract_document_number("CRECI", "creci"),
                self._extract_document_number("CNPJ", "cnpj"),
                self._extract_document_number("RFC", "rfc"),
            )
            .withColumnRenamed("id_company", "doc_id_company")
        )

    def _process_company_product(self, company_product_df):
        """Aggregate 3P product flags per company (products 27=sale, 30=rent)."""
        filtered = company_product_df.filter(col("id_product").isin([27, 30]))

        return filtered.groupBy("id_company").agg(
            spark_max(
                when(col("id_product") == 30, lit(True)).otherwise(lit(False))
            ).alias("is_3p_rent_broker"),
            spark_max(
                when(col("id_product") == 27, lit(True)).otherwise(lit(False))
            ).alias("is_3p_sale_broker"),
            spark_max(
                when(
                    col("id_product").isin([27, 30]) & (col("status") == "ACTIVE"),
                    lit(True),
                ).otherwise(lit(False))
            ).alias("is_3p_active_broker"),
            spark_max(
                when(
                    (col("id_product") == 30) & (col("status") == "ACTIVE"),
                    lit(True),
                ).otherwise(lit(False))
            ).alias("is_3p_active_rent_broker"),
            spark_max(
                when(
                    (col("id_product") == 27) & (col("status") == "ACTIVE"),
                    lit(True),
                ).otherwise(lit(False))
            ).alias("is_3p_active_sale_broker"),
        )

    def _join_all_data(
        self,
        company_df,
        company_address_df,
        company_document_df,
        company_product_df,
        address_df,
    ):
        """Join all data sources. Only companies with 3P products are kept."""
        result_df = company_df.alias("c")

        result_df = result_df.join(
            company_product_df.alias("cp"),
            col("c.id") == col("cp.id_company"),
            "inner",
        )

        result_df = result_df.join(
            company_address_df.alias("ca"),
            col("c.id") == col("ca.id_company"),
            "left",
        )

        result_df = result_df.join(
            company_document_df.alias("cd"),
            col("c.id") == col("cd.doc_id_company"),
            "left",
        )

        result_df = result_df.join(
            address_df.alias("a"),
            col("ca.id_address") == col("a.id"),
            "left",
        )

        return result_df

    def _select_final_columns(self, result_df, extra_columns=None):
        """Select and alias the final output columns.

        Args:
            result_df: Joined DataFrame
            extra_columns: Optional list of additional Column expressions
                to append (e.g. CDC metadata columns for historical table)
        """
        columns = [
            col("c.id").cast("string").alias("sk_broker"),
            col("c.id").alias("id_company"),
            col("c.uuid_company"),
            col("c.company_name").alias("broker_name"),
            col("c.trade_name").alias("broker_trade_name"),
            when(col("cp.is_3p_active_broker"), lit("ACTIVE"))
            .otherwise(lit("INACTIVE"))
            .alias("broker_status"),
            col("c.status").alias("company_status"),
            col("a.public_area").alias("broker_address"),
            col("a.number").alias("broker_number"),
            col("a.complement").alias("broker_complement"),
            col("a.neighborhood").alias("broker_neighborhood"),
            col("a.city").alias("broker_city"),
            col("a.state").alias("broker_state"),
            col("a.country").alias("broker_country"),
            col("a.zip_code").alias("broker_zip_code"),
            col("cd.creci"),
            col("cd.cnpj"),
            col("cd.rfc"),
            col("cp.is_3p_rent_broker"),
            col("cp.is_3p_sale_broker"),
            col("cp.is_3p_active_broker"),
            col("cp.is_3p_active_rent_broker"),
            col("cp.is_3p_active_sale_broker"),
            col("c.ts_created"),
            col("c.ts_updated"),
            current_timestamp().alias("ts_load"),
        ]

        if extra_columns:
            columns.extend(extra_columns)

        return result_df.select(*columns)

    # ── run_pipeline override ───────────────────────────────────────

    def run_pipeline(self, dataframe: DataFrame, args, spark: SparkSession) -> None:
        """Override to use table-specific merge config for historical table.

        The historical table does NOT use the base class's "preserve non-null"
        when_matched_operation because each row is a complete snapshot of a
        CDC transaction, not a partial update.
        """
        if args.table_name == HISTORICAL_TABLE:
            self._run_pipeline_with_config(
                dataframe,
                args,
                spark,
                merge_on_key="merge_on_historical",
                update_condition_key="when_matched_update_condition_historical",
            )
        else:
            super().run_pipeline(dataframe, args, spark)


if __name__ == "__main__":
    job = CoreBrokersSparkJob()
    job.run()