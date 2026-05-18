from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import (
    col,
    current_timestamp,
    last,
    lit,
    max as spark_max,
    regexp_replace,
    translate,
    when,
)

from bietlejuice.base.core_models.core_brokers_base import (
    CoreBrokersBaseSparkJob,
)

_BROKER_STRING_TAG_ACCENT_FROM = (
    "áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ"
)
_BROKER_STRING_TAG_ACCENT_TO = (
    "aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC"
)


def _broker_string_tag(column):
    """Remove accents and whitespace; preserve letter case; NULL in yields NULL out."""
    return when(column.isNull(), lit(None).cast("string")).otherwise(
        regexp_replace(
            translate(column, _BROKER_STRING_TAG_ACCENT_FROM, _BROKER_STRING_TAG_ACCENT_TO),
            r"\s+",
            "",
        )
    )


class CoreBrokersSparkJob(CoreBrokersBaseSparkJob):
    """Core Brokers Spark job implementation.

    Consolidates broker partner data from the 3P Partners operation,
    joining company, address, document and product information into
    a single denormalized view of each broker (current state from the
    clean layer).
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

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
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
        return self._add_partition_columns(result_df, "ts_broker_updated")

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
    def _extract_document_number(doc_type, alias_name, digits_only: bool):
        """Build an aggregate expression that extracts a cleaned document number.

        CNPJ uses digits-only; CRECI and RFC keep alphanumeric characters.

        Returns a ``Column`` expression suitable for use inside ``.agg()``.
        """
        pattern = "[^0-9]" if digits_only else "[^0-9A-Za-z]"
        cleaned = regexp_replace(col("d.identification_number"), pattern, "")
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
                self._extract_document_number("CRECI", "creci", digits_only=False),
                self._extract_document_number("CNPJ", "cnpj", digits_only=True),
                self._extract_document_number("RFC", "rfc", digits_only=False),
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

    def _select_final_columns(self, result_df):
        """Select and alias the final output columns."""
        return result_df.select(
            col("c.id").cast("string").alias("sk_broker"),
            col("c.id").alias("id_company"),
            col("c.uuid_company"),
            col("c.company_name").alias("broker_name"),
            col("c.trade_name").alias("broker_trade_name"),
            _broker_string_tag(col("c.company_name")).alias("broker_name_tag"),
            _broker_string_tag(col("c.trade_name")).alias("broker_trade_name_tag"),
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
            regexp_replace(col("a.zip_code"), "[^0-9]", "").alias("broker_zip_code"),
            col("cd.creci"),
            col("cd.cnpj"),
            col("cd.rfc"),
            col("cp.is_3p_rent_broker"),
            col("cp.is_3p_sale_broker"),
            col("cp.is_3p_active_broker"),
            col("cp.is_3p_active_rent_broker"),
            col("cp.is_3p_active_sale_broker"),
            lit(True).alias("has_3p_access_control"),
            col("c.ts_created").alias("ts_broker_created"),
            col("c.ts_updated").alias("ts_broker_updated"),
            current_timestamp().alias("ts_load"),
        )


if __name__ == "__main__":
    job = CoreBrokersSparkJob()
    job.run()
