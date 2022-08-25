from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    DoubleType,
    IntegerType,
)


class SapSchemaEnum:
    """This class contains the Spark schemas for the tables loaded by the SAP Consumer."""

    JOURNAL_ENTRIES_SCHEMA = StructType(
        [
            StructField("AccrualDate (Ref3)", StringType(), True),
            StructField("Business Entity ID (Ref1)", StringType(), True),
            StructField("CreateDate", StringType(), True),
            StructField("CreatedBy (UserSign)", IntegerType(), True),
            StructField("DocDate", StringType(), True),
            StructField("DocEntry", StringType(), True),
            StructField("DueDate", StringType(), True),
            StructField(
                "External Payment ID (U_ExternalPaymentId)", StringType(), True
            ),
            StructField("Financial Entity ID (Ref2)", StringType(), True),
            StructField("LocTotal", DoubleType(), True),
            StructField("Memo", StringType(), True),
            StructField("RefDate", StringType(), True),
            StructField("Source Client (U_SourceClient)", StringType(), True),
            StructField("TaxDate", StringType(), True),
            StructField("Transaction ID (TransId)", StringType(), True),
            StructField("Transaction Type (TransType)", StringType(), True),
            StructField("UUID (U_RSD_UUID)", StringType(), True),
            StructField("UpdateDate", StringType(), True),
            StructField("UpdatedBy", StringType(), True),
        ]
    )

    JOURNAL_ENTRY_LINES = StructType(
        [
            StructField("Account (Account)", StringType(), True),
            StructField("Account (ShortName)", StringType(), True),
            StructField("AccrualDate (Ref3Line)", StringType(), True),
            StructField("Business Entity ID (Ref1)", StringType(), True),
            StructField("Cost Center (OcrCode2)", StringType(), True),
            StructField("Credit", DoubleType(), True),
            StructField("Debit", DoubleType(), True),
            StructField("DueDate", StringType(), True),
            StructField(
                "Finance Entity Entry ID (U_FinanceEntityEntryId)", StringType(), True
            ),
            StructField("Finance Entity ID (Ref2)", StringType(), True),
            StructField("Line ID (Line_ID)", IntegerType(), True),
            StructField("Location (ProfitCode)", StringType(), True),
            StructField("Managerial (OcrCode3)", StringType(), True),
            StructField("Memo (LineMemo)", StringType(), True),
            StructField("RefDate", StringType(), True),
            StructField("TaxDate", StringType(), True),
            StructField("Transaction ID (TransId)", StringType(), True),
            StructField("Transaction Type (TransType)", StringType(), True),
        ]
    )

    INVOICES = StructType(
        [
            StructField("AccrualDate (U_AccrualDate)", StringType(), True),
            StructField("Business Entity ID (NumAtCard)", StringType(), True),
            StructField("CreateDate", StringType(), True),
            StructField("CreatedBy (UserSign)", IntegerType(), True),
            StructField("DocDate", StringType(), True),
            StructField("DocEntry", IntegerType(), True),
            StructField("DueDate", StringType(), True),
            StructField(
                "External Payment ID (U_ExternalPaymentId)", StringType(), True
            ),
            StructField(
                "Financial Entity Entry ID (U_FinancialEntityEntryId)",
                StringType(),
                True,
            ),
            StructField("Financial Entity ID (Ref2)", StringType(), True),
            StructField("Legacy UUID (U_RSD_UUIDSB)", StringType(), True),
            StructField("LocTotal", DoubleType(), True),
            StructField("Memo", StringType(), True),
            StructField("RefDate", StringType(), True),
            StructField("Source Client (U_SourceClient)", StringType(), True),
            StructField("TaxDate", StringType(), True),
            StructField("Transaction ID (TransId)", IntegerType(), True),
            StructField("Transaction Type (TransType)", StringType(), True),
            StructField("UUID (U_RSD_UUID)", StringType(), True),
            StructField("UpdateDate", StringType(), True),
            StructField("UpdatedBy (UserSign2)", IntegerType(), True),
        ]
    )

    INCOMING_PAYMENTS = StructType(
        [
            StructField("AccrualDate (U_AccrualDate)", StringType(), True),
            StructField("Business Entity ID (U_BusinessEntityId)", StringType(), True),
            StructField("CreateDate", StringType(), True),
            StructField("CreatedBy (UserSign)", IntegerType(), True),
            StructField("DocDate", StringType(), True),
            StructField("DocEntry", IntegerType(), True),
            StructField("DueDate", StringType(), True),
            StructField(
                "External Payment ID (U_ExternalPaymentId)", StringType(), True
            ),
            StructField("Financial Entity ID (U_FinanceEntityId))", StringType(), True),
            StructField("Legacy UUID (U_RSD_UUIDSB)", StringType(), True),
            StructField("LocTotal", DoubleType(), True),
            StructField("Memo", StringType(), True),
            StructField("RefDate", StringType(), True),
            StructField("Source Client (U_SourceClient)", StringType(), True),
            StructField("TaxDate", StringType(), True),
            StructField("Transaction ID (TransId)", IntegerType(), True),
            StructField("Transaction Type (TransType)", StringType(), True),
            StructField("UUID (U_OINV_UUID)", StringType(), True),
            StructField("UpdateDate", StringType(), True),
            StructField("UpdatedBy (UserSign2)", IntegerType(), True),
        ]
    )
