from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import (
    col,
    concat,
    concat_ws,
    coalesce,
    current_timestamp,
    last,
    lit,
    max as spark_max,
    regexp_replace,
    year,
    month,
    dayofmonth,
    when,
    collect_list,
    get_json_object,
)

from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.base.core_models.helpers.surrogate_keys import SurrogateKeysHelper

JOB_NAME = "core_company"


class CoreCompanySparkJob(BaseCoreModelSparkJob):
    """Core Company Spark job implementation."""

    def __init__(self):
        """Initialize the Core Company Spark job."""
        super().__init__(JOB_NAME)

    def get_company_config(self):
        """Get company-specific configuration."""
        return {
            'ENTITY_TYPE': self.get_config("ENTITY_TYPE"),
            'COMPANY_TABLE': self.get_config("COMPANY_TABLE"),
            'COMPANY_ADDRESS_TABLE': self.get_config("COMPANY_ADDRESS_TABLE"),
            'COMPANY_DOCUMENT_TABLE': self.get_config("COMPANY_DOCUMENT_TABLE"),
            'DOCUMENT_TABLE': self.get_config("DOCUMENT_TABLE"),
            'COMPANY_PRODUCT_TABLE': self.get_config("COMPANY_PRODUCT_TABLE"),
            'ADDRESS_TABLE': self.get_config("ADDRESS_TABLE"),
            'PRODUCT_TABLE': self.get_config("PRODUCT_TABLE"),
            'REVENUE_SHARE_TABLE': self.get_config("REVENUE_SHARE_TABLE"),
            'BANKING_INFORMATION_TABLE': self.get_config("BANKING_INFORMATION_TABLE"),
            'TIER_TABLE': self.get_config("TIER_TABLE"),
            'COMPANY_PRODUCT_TIER_TABLE': self.get_config("COMPANY_PRODUCT_TIER_TABLE"),
            'COMPANY_PRODUCT_REGION_TABLE': self.get_config("COMPANY_PRODUCT_REGION_TABLE"),
        }

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        """Create the core company model from Company domain data."""

        # Load configuration
        config = self.get_company_config()

        # Load source data
        company_df = self._load_data(spark, config['COMPANY_TABLE'], args, apply_date_filter=True)
        company_address_df = self._load_data(spark, config['COMPANY_ADDRESS_TABLE'], args)
        company_document_df = self._load_data(spark, config['COMPANY_DOCUMENT_TABLE'], args)
        document_df = self._load_data(spark, config['DOCUMENT_TABLE'], args)
        company_product_df = self._load_data(spark, config['COMPANY_PRODUCT_TABLE'], args)
        address_df = self._load_data(spark, config['ADDRESS_TABLE'], args)
        product_df = self._load_data(spark, config['PRODUCT_TABLE'], args)
        revenue_share_df = self._load_data(spark, config['REVENUE_SHARE_TABLE'], args)
        banking_information_df = self._load_data(spark, config['BANKING_INFORMATION_TABLE'], args)
        tier_df = self._load_data(spark, config['TIER_TABLE'], args)
        company_product_tier_df = self._load_data(spark, config['COMPANY_PRODUCT_TIER_TABLE'], args)
        company_product_region_df = self._load_data(spark, config['COMPANY_PRODUCT_REGION_TABLE'], args)

        # Process CTEs
        company_address_processed = self._process_company_address(company_address_df)
        company_document_processed = self._process_company_document(company_document_df, document_df)
        company_product_processed = self._process_company_product(company_product_df)

        # Join all data
        result_df = self._join_all_data(
            company_df,
            company_address_processed,
            company_document_processed,
            company_product_processed,
            company_product_tier_df,
            company_product_region_df,
            address_df,
            product_df,
            revenue_share_df,
            banking_information_df,
            tier_df
        )

        # Add partitioning columns
        result_df = result_df.withColumn("year", year(col("ts_company_updated"))) \
                            .withColumn("month", month(col("ts_company_updated"))) \
                            .withColumn("day", dayofmonth(col("ts_company_updated")))

        return result_df

    def _load_data(self, spark, table_name, args, apply_date_filter=False):
        """Load and filter data from a table.
        
        Args:
            spark: SparkSession instance
            table_name: Full table name to load from
            args: Job arguments
            apply_date_filter: Whether to apply incremental date filter (default: False)
        
        Returns:
            DataFrame with loaded data
        """
        df = spark.read.table(table_name)

        # Apply date filter if requested (for incremental loads)
        if (apply_date_filter and 
            args.load_start_date is not None and args.load_start_date != "" and
            args.load_end_date is not None and args.load_end_date != ""):
            df = df.filter(
                (col("ts_updated").cast("date") >= lit(args.load_start_date).cast("date")) &
                (col("ts_updated").cast("date") <= lit(args.load_end_date).cast("date"))
            )

        return df

    def _process_company_address(self, company_address_df):
        """Process company address to get the last address per company."""
        return company_address_df.groupBy("id_company").agg(
            last("id_address").alias("id_address")
        )

    def _process_company_document(self, company_document_df, document_df):
        """Process company document to extract CRECI, CNPJ, and RFC."""
        # Join company_document with document
        cd_with_doc = company_document_df.alias("cd").join(
            document_df.alias("d").filter(col("status") == "ACTIVE"),
            col("cd.id_document") == col("d.id"),
            "left"
        )

        # Extract different document types
        return cd_with_doc.groupBy("cd.id_company").agg(
            when(
                spark_max(
                    when(col("d.document_type") == "CRECI", 
                         regexp_replace(col("d.identification_number"), "[^0-9]", ""))
                ) != "",
                spark_max(
                    when(col("d.document_type") == "CRECI", 
                         regexp_replace(col("d.identification_number"), "[^0-9]", ""))
                )
            ).alias("creci"),
            when(
                spark_max(
                    when(col("d.document_type") == "CNPJ", 
                         regexp_replace(col("d.identification_number"), "[^0-9]", ""))
                ) != "",
                spark_max(
                    when(col("d.document_type") == "CNPJ", 
                         regexp_replace(col("d.identification_number"), "[^0-9]", ""))
                )
            ).alias("cnpj"),
            when(
                spark_max(
                    when(col("d.document_type") == "RFC", 
                         regexp_replace(col("d.identification_number"), "[^0-9]", ""))
                ) != "",
                spark_max(
                    when(col("d.document_type") == "RFC", 
                         regexp_replace(col("d.identification_number"), "[^0-9]", ""))
                )
            ).alias("rfc")
        ).withColumnRenamed("id_company", "doc_id_company")

    def _process_company_product(self, company_product_df):
        """Process company product to extract settings from JSON."""
        return company_product_df.select(
            col("id_company"),
            col("id_product"),
            get_json_object(col("product_settings"), "$.bankingInformationUUId").alias("uuid_banking_information"),
            get_json_object(col("product_settings"), "$.integratorPartnerUUId").alias("uuid_integrator_partner"),
            get_json_object(col("product_settings"), "$.revenueShareUUId").alias("uuid_revenue_share"),
            get_json_object(col("product_settings"), "$.optInNavent").alias("has_opt_in_navent")
        )

    def _join_all_data(self, company_df, company_address_df, company_document_df,
                       company_product_df, company_product_tier_df, company_product_region_df,
                       address_df, product_df, revenue_share_df, banking_information_df, tier_df):
        """Join all data sources to create the final result."""

        # Start with company data
        result_df = company_df.alias("c")

        # Join with company_address
        result_df = result_df.join(
            company_address_df.alias("ca"),
            col("c.id") == col("ca.id_company"),
            "left"
        )

        # Join with company_document
        result_df = result_df.join(
            company_document_df.alias("cd"),
            col("c.id") == col("cd.doc_id_company"),
            "left"
        )

        # Join with company_product
        result_df = result_df.join(
            company_product_df.alias("cp"),
            col("c.id") == col("cp.id_company"),
            "left"
        )

        # Join with company_product_tier
        result_df = result_df.join(
            company_product_tier_df.alias("ct"),
            (col("c.id") == col("ct.id_company")) &
            (col("ct.id_product") == col("cp.id_product")),
            "left"
        )

        # Join with company_product_region (will aggregate later)
        result_df = result_df.join(
            company_product_region_df.alias("r"),
            (col("r.id_company") == col("c.id")) &
            (col("r.id_product") == col("cp.id_product")),
            "left"
        )

        # Join with address
        result_df = result_df.join(
            address_df.alias("a"),
            col("ca.id_address") == col("a.id"),
            "left"
        )

        # Join with product
        result_df = result_df.join(
            product_df.alias("p"),
            col("p.id") == col("cp.id_product"),
            "left"
        )

        # Join with integrator partner (self-join with company)
        result_df = result_df.join(
            company_df.alias("ip"),
            col("cp.uuid_integrator_partner") == col("ip.uuid_company"),
            "left"
        )

        # Join with revenue_share
        result_df = result_df.join(
            revenue_share_df.alias("rs"),
            col("cp.uuid_revenue_share") == col("rs.uuid_revenue_share"),
            "left"
        )

        # Join with banking_information
        result_df = result_df.join(
            banking_information_df.alias("bi"),
            col("cp.uuid_banking_information") == col("bi.uuid_banking_information"),
            "left"
        )

        # Join with tier
        result_df = result_df.join(
            tier_df.alias("t"),
            col("ct.id_tier") == col("t.id"),
            "left"
        )

        # Group by and aggregate regions
        result_df = result_df.groupBy(
            col("c.id"),
            col("c.id_parent"),
            col("p.id"),
            col("c.uuid_company"),
            col("c.company_name"),
            col("c.trade_name"),
            col("c.company_type"),
            col("c.status"),
            col("c.version"),
            col("a.public_area"),
            col("a.number"),
            col("a.complement"),
            col("a.neighborhood"),
            col("a.city"),
            col("a.state"),
            col("a.country"),
            col("a.zip_code"),
            col("cd.creci"),
            col("cd.cnpj"),
            col("cd.rfc"),
            col("p.name"),
            col("p.business_segment"),
            col("ip.company_name"),
            col("ip.status"),
            col("rs.commission"),
            col("rs.demand_fee"),
            col("rs.supply_fee"),
            col("rs.platform_fee"),
            col("bi.bank"),
            col("bi.agency_number"),
            col("bi.account_number"),
            col("bi.type"),
            col("t.tier_name"),
            col("cp.has_opt_in_navent"),
            col("c.ts_created"),
            col("c.ts_updated"),
            col("c.year"),
            col("c.month"),
            col("c.day")
        ).agg(
            when(
                concat_ws(",", collect_list(col("r.id_region"))) != "",
                concat_ws(",", collect_list(col("r.id_region")))
            ).otherwise(lit(None)).alias("id_region_list")
        )

        # Select final columns with proper aliases and calculated fields
        return result_df.select(
            concat(col("c.id"), coalesce(col("p.id"), lit(0))).alias("sk_company"),
            col("c.id").alias("id_company"),
            col("c.id_parent"),
            col("p.id").alias("id_product"),
            col("c.uuid_company"),
            col("c.company_name"),
            col("c.trade_name"),
            col("c.company_type"),
            col("c.status").alias("company_status"),
            col("c.version").alias("company_version"),
            col("a.public_area").alias("address"),
            col("a.number").alias("address_number"),
            col("a.complement").alias("address_complement"),
            col("a.neighborhood"),
            col("a.city"),
            col("a.state"),
            col("a.country"),
            regexp_replace(col("a.zip_code"), "[^0-9]", "").alias("zip_code"),
            col("cd.creci"),
            col("cd.cnpj"),
            col("cd.rfc"),
            col("p.name").alias("product_name"),
            col("p.business_segment"),
            col("ip.company_name").alias("integrator_partner"),
            col("ip.status").alias("integrator_partner_status"),
            col("rs.commission"),
            col("rs.demand_fee"),
            col("rs.supply_fee"),
            col("rs.platform_fee"),
            col("bi.bank").alias("account_bank"),
            col("bi.agency_number"),
            col("bi.account_number"),
            col("bi.type").alias("account_type"),
            col("t.tier_name"),
            col("id_region_list"),
            (col("c.status") == "ACTIVE").alias("is_active_company"),
            col("p.id").isin([27, 30]).alias("has_3p_access_control"),
            col("cp.has_opt_in_navent"),
            col("c.ts_created").alias("ts_company_created"),
            col("c.ts_updated").alias("ts_company_updated"),
            current_timestamp().alias("ts_load"),
            col("c.year"),
            col("c.month"),
            col("c.day")
        )


if __name__ == "__main__":
    job = CoreCompanySparkJob()
    job.run()