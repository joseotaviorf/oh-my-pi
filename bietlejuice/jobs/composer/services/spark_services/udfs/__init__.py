from bietlejuice.jobs.composer.services.spark_services.udfs.string_formatter_udf import (
    StringFormatterUDF,
)

SF_REMOVE_ACCENTUATION = "sf_remove_accentuation"

UDFS = {SF_REMOVE_ACCENTUATION: StringFormatterUDF.remove_accentuation}
