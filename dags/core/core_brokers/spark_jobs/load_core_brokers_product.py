from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import (
    array_distinct,
    array_join,
    col,
    collect_list,
    concat,
    current_timestamp,
    get_json_object,
)

from bietlejuice.base.core_models.core_brokers_base import (
    CoreBrokersBaseSparkJob,
)
from bietlejuice.base.core_models.helpers.historical_helper import HistoricalHelper

HISTORICAL_TABLE = "brokers_product_historical"


class CoreBrokersProductSparkJob(CoreBrokersBaseSparkJob):
    """Core Brokers Product Spark job implementation.

    Consolidates broker-product relationship data from the 3P Partners
    operation, joining company, product, revenue share, banking information,
    integrator partner, tier, and region data into a denormalized view
    at the company-product level.

    Supports two output tables:
      - ``brokers_product`` (current state from clean layer)
      - ``brokers_product_historical`` (all CDC transactions from transactional layer)
    """

    def get_brokers_product_config(self):
        """Get broker-product-specific configuration from forno_conf/prod_conf."""
        return {
            "COMPANY_TABLE": self.get_config("COMPANY_TABLE"),
            "COMPANY_PRODUCT_TABLE": self.get_config("COMPANY_PRODUCT_TABLE"),
            "PRODUCT_TABLE": self.get_config("PRODUCT_TABLE"),
            "COMPANY_PRODUCT_REGION_TABLE": self.get_config(
                "COMPANY_PRODUCT_REGION_TABLE"
            ),
            "REVENUE_SHARE_TABLE": self.get_config("REVENUE_SHARE_TABLE"),
            "BANKING_INFORMATION_TABLE": self.get_config("BANKING_INFORMATION_TABLE"),
            "TIER_TABLE": self.get_config("TIER_TABLE"),
            "COMPANY_PRODUCT_TIER_TABLE": self.get_config("COMPANY_PRODUCT_TIER_TABLE"),
        }

    # ── create_core_model dispatch ──────────────────────────────────

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        """Dispatch to the appropriate model builder based on table_name."""
        if args.table_name == HISTORICAL_TABLE:
            return self._create_historical_model(spark, args)
        return self._create_current_state_model(spark, args)

    # ── current-state model (brokers_product) ────────────────────────

    def _create_current_state_model(self, spark: SparkSession, args) -> DataFrame:
        """Create the current-state brokers product model from clean layer."""
        config = self.get_brokers_product_config()

        company_df = self._load_data(
            spark, config["COMPANY_TABLE"], args, apply_date_filter=True
        )
        company_product_df = self._load_data(
            spark, config["COMPANY_PRODUCT_TABLE"], args
        )
        product_df = self._load_data(spark, config["PRODUCT_TABLE"], args)
        company_product_region_df = self._load_data(
            spark, config["COMPANY_PRODUCT_REGION_TABLE"], args
        )
        revenue_share_df = self._load_data(spark, config["REVENUE_SHARE_TABLE"], args)
        banking_information_df = self._load_data(
            spark, config["BANKING_INFORMATION_TABLE"], args
        )
        tier_df = self._load_data(spark, config["TIER_TABLE"], args)
        company_product_tier_df = self._load_data(
            spark, config["COMPANY_PRODUCT_TIER_TABLE"], args
        )

        result_df = self._transform_and_join(
            company_df,
            company_product_df,
            product_df,
            company_product_region_df,
            revenue_share_df,
            banking_information_df,
            tier_df,
            company_product_tier_df,
        )

        result_df = self._select_final_columns(result_df)
        return self._add_partition_columns(result_df, "ts_updated")

    # ── historical model (brokers_product_historical) ────────────────

    def _create_historical_model(self, spark: SparkSession, args) -> DataFrame:
        """Create the historical brokers product model.

        Company-product transactions come from the transactional layer (every
        insert, update, delete). Related entities (company, product, region,
        etc.) are joined from the clean layer to provide the latest context
        for each transaction.
        """
        config = self.get_brokers_product_config()

        transactional_table = self.get_config("COMPANY_PRODUCT_TRANSACTIONAL_TABLE")
        company_product_df = HistoricalHelper.load_transactional_data(
            spark,
            transactional_table,
            args,
        )
        company_product_df = company_product_df.withColumnRenamed(
            "product_id", "id_product"
        ).withColumnRenamed("company_id", "id_company")

        company_df = self._load_data(spark, config["COMPANY_TABLE"], args)
        product_df = self._load_data(spark, config["PRODUCT_TABLE"], args)
        company_product_region_df = self._load_data(
            spark, config["COMPANY_PRODUCT_REGION_TABLE"], args
        )
        revenue_share_df = self._load_data(spark, config["REVENUE_SHARE_TABLE"], args)
        banking_information_df = self._load_data(
            spark, config["BANKING_INFORMATION_TABLE"], args
        )
        tier_df = self._load_data(spark, config["TIER_TABLE"], args)
        company_product_tier_df = self._load_data(
            spark, config["COMPANY_PRODUCT_TIER_TABLE"], args
        )

        result_df = self._transform_and_join(
            company_df,
            company_product_df,
            product_df,
            company_product_region_df,
            revenue_share_df,
            banking_information_df,
            tier_df,
            company_product_tier_df,
            include_cdc_columns=True,
        )

        cdc_cols = HistoricalHelper.select_cdc_columns(company_product_df, "cp")
        result_df = self._select_final_columns(result_df, extra_columns=cdc_cols)
        result_df = self._add_is_current(result_df, "sk_broker_product")
        return self._add_partition_columns(result_df, "ts_database_transaction")

    # ── shared transformation logic ─────────────────────────────────

    def _transform_and_join(
        self,
        company_df,
        company_product_df,
        product_df,
        company_product_region_df,
        revenue_share_df,
        banking_information_df,
        tier_df,
        company_product_tier_df,
        include_cdc_columns=False,
    ) -> DataFrame:
        """Process sub-entities and join everything at the company-product level."""
        company_product_processed = self._process_company_product(
            company_product_df,
            include_cdc_columns=include_cdc_columns,
        )
        company_product_region_processed = self._process_company_product_region(
            company_product_region_df
        )

        return self._join_all_data(
            company_df,
            company_product_processed,
            product_df,
            company_product_region_processed,
            revenue_share_df,
            banking_information_df,
            tier_df,
            company_product_tier_df,
        )

    def _process_company_product(self, company_product_df, include_cdc_columns=False):
        """Extract JSON settings and compute boolean flags per company-product.

        Filters for 3P products (27=sale, 30=rent) and extracts banking,
        integrator partner, revenue share UUIDs and opt-in flag from the
        product_settings JSON column.

        Args:
            company_product_df: DataFrame with company-product data
            include_cdc_columns: If True, preserve CDC metadata columns
                (op_cdc, ts_database_transaction, ts_cdc_transaction)
                needed by the historical table path
        """
        filtered = company_product_df.filter(col("id_product").isin([27, 30]))

        columns = [
            col("id_company"),
            col("id_product"),
            get_json_object(col("product_settings"), "$.bankingInformationUUId").alias(
                "uuid_banking_information"
            ),
            get_json_object(col("product_settings"), "$.integratorPartnerUUId").alias(
                "uuid_integrator_partner"
            ),
            get_json_object(col("product_settings"), "$.revenueShareUUId").alias(
                "uuid_revenue_share"
            ),
            col("status"),
            (col("id_product") == 30).alias("is_3p_rent_broker"),
            (col("id_product") == 27).alias("is_3p_sale_broker"),
            (col("id_product").isin([27, 30]) & (col("status") == "ACTIVE")).alias(
                "is_3p_active_broker"
            ),
            ((col("id_product") == 30) & (col("status") == "ACTIVE")).alias(
                "is_3p_active_rent_broker"
            ),
            ((col("id_product") == 27) & (col("status") == "ACTIVE")).alias(
                "is_3p_active_sale_broker"
            ),
            get_json_object(col("product_settings"), "$.optInNavent").alias(
                "has_opt_in_navent"
            ),
        ]

        if include_cdc_columns:
            columns.extend(
                [
                    col("op_cdc"),
                    col("ts_database_transaction"),
                    col("ts_cdc_transaction"),
                ]
            )

        return filtered.select(*columns)

    def _process_company_product_region(self, company_product_region_df):
        """Aggregate regions into a comma-separated string per company-product pair."""
        return company_product_region_df.groupBy("id_company", "id_product").agg(
            array_join(
                array_distinct(collect_list(col("id_region").cast("string"))),
                ",",
            ).alias("region_list")
        )

    def _join_all_data(
        self,
        company_df,
        company_product_df,
        product_df,
        company_product_region_df,
        revenue_share_df,
        banking_information_df,
        tier_df,
        company_product_tier_df,
    ):
        """Join all data sources at the company-product level.

        Only companies with processed company_product records are kept
        (equivalent to WHERE cp.id_company IS NOT NULL).
        """
        result_df = company_df.alias("c")

        result_df = result_df.join(
            company_product_df.alias("cp"),
            col("c.id") == col("cp.id_company"),
            "inner",
        )

        result_df = result_df.join(
            company_product_tier_df.alias("ct"),
            (col("c.id") == col("ct.id_company"))
            & (col("cp.id_product") == col("ct.id_product")),
            "left",
        )

        result_df = result_df.join(
            company_product_region_df.alias("cpr"),
            (col("c.id") == col("cpr.id_company"))
            & (col("cp.id_product") == col("cpr.id_product")),
            "left",
        )

        result_df = result_df.join(
            product_df.alias("p"),
            col("cp.id_product") == col("p.id"),
            "left",
        )

        result_df = result_df.join(
            company_df.alias("ip"),
            col("cp.uuid_integrator_partner") == col("ip.uuid_company"),
            "left",
        )

        result_df = result_df.join(
            revenue_share_df.alias("rs"),
            col("cp.uuid_revenue_share") == col("rs.uuid_revenue_share"),
            "left",
        )

        result_df = result_df.join(
            banking_information_df.alias("bi"),
            col("cp.uuid_banking_information") == col("bi.uuid_banking_information"),
            "left",
        )

        result_df = result_df.join(
            tier_df.alias("t"),
            col("ct.id_tier") == col("t.id"),
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
            concat(
                col("c.id").cast("string"),
                col("p.id").cast("string"),
            ).alias("sk_broker_product"),
            col("c.id").cast("string").alias("sk_broker"),
            col("c.id").alias("id_company"),
            col("c.uuid_company"),
            col("c.company_name").alias("broker_name"),
            col("c.trade_name").alias("broker_trade_name"),
            col("p.name").alias("product_name"),
            col("p.business_segment"),
            col("cp.status").alias("product_status"),
            col("ip.company_name").alias("integrator_partner"),
            col("ip.status").alias("integrator_partner_status"),
            col("rs.commission"),
            col("rs.demand_fee"),
            col("rs.supply_fee"),
            col("rs.platform_fee"),
            col("bi.bank"),
            col("bi.agency_number"),
            col("bi.account_number"),
            col("bi.type").alias("account_type"),
            col("t.tier_name"),
            col("cp.is_3p_rent_broker"),
            col("cp.is_3p_sale_broker"),
            col("cp.is_3p_active_broker"),
            col("cp.is_3p_active_rent_broker"),
            col("cp.is_3p_active_sale_broker"),
            col("cp.has_opt_in_navent"),
            col("cpr.region_list"),
            col("c.ts_created"),
            col("c.ts_updated"),
            current_timestamp().alias("ts_load"),
        ]

        if extra_columns:
            columns.extend(extra_columns)

        return result_df.select(*columns)

    # ── run_pipeline override ───────────────────────────────────────

    def run_pipeline(self, dataframe: DataFrame, args, spark: SparkSession) -> None:
        """Override to use brokers_product-specific merge configs.

        Both current state and historical tables use dedicated merge keys
        (merge_on_brokers_product / merge_on_brokers_product_historical)
        instead of the base class defaults.
        """
        if args.table_name == HISTORICAL_TABLE:
            self._run_pipeline_with_config(
                dataframe,
                args,
                spark,
                merge_on_key="merge_on_brokers_product_historical",
                update_condition_key=(
                    "when_matched_update_condition_brokers_product_historical"
                ),
            )
        else:
            self._run_pipeline_with_config(
                dataframe,
                args,
                spark,
                merge_on_key="merge_on_brokers_product",
                update_condition_key=("when_matched_update_condition_brokers_product"),
            )


if __name__ == "__main__":
    job = CoreBrokersProductSparkJob()
    job.run()
