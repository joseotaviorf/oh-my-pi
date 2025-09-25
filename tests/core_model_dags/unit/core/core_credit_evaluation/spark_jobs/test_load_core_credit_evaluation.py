"""
Unit tests for CoreCreditEvaluationSparkJob.
"""

from unittest.mock import Mock, patch
from argparse import Namespace

from dags.core.core_credit_evaluation.spark_jobs.load_core_credit_evaluation import (
    CoreCreditEvaluationSparkJob,
)


class TestCoreCreditEvaluationSparkJob:
    """Test class for CoreCreditEvaluationSparkJob."""

    def test_create_core_model_basic_functionality(
        self,
        spark_session,
        credit_evaluation_df,
        house_df,
        house_listing_relation_df,
        user_df,
        mock_configuration_service,
        mock_surrogate_keys_helper,
    ):
        """Test basic functionality of create_core_model method."""

        # Create a mock for spark.read
        mock_read = Mock()

        # Configure mock to return appropriate DataFrame based on table name
        def mock_table_side_effect(table_name):
            if table_name == "test.credit_evaluation":
                return credit_evaluation_df
            elif table_name == "test.house":
                return house_df
            elif table_name == "test.house_listing_relation":
                return house_listing_relation_df
            elif table_name == "test.user":
                return user_df
            else:
                raise ValueError(f"Unknown table: {table_name}")

        mock_read.table.side_effect = mock_table_side_effect

        # Mock table reads
        with patch.object(
            type(spark_session), "read", new_callable=lambda: mock_read, create=True
        ):

            # Create job and run
            job = CoreCreditEvaluationSparkJob()
            args = Namespace(load_start_date=None, load_end_date=None)
            result_df = job.create_core_model(spark_session, args)

            # Assertions
            assert result_df is not None
            result_data = result_df.collect()
            assert len(result_data) > 0

            # Check that basic columns exist
            columns = result_df.columns
            expected_columns = [
                "id_credit_evaluation",
                "id_house",
                "id_proposal",
                "id_user",
                "id_city",
                "id_group",
                "reason",
                "result",
                "early_result",
                "limit_value",
                "user_pre_approved_limit",
                "status",
                "documentation_policy_type",
                "is_early_credit",
                "is_credit_passport",
                "is_bypass",
                "ts_created",
                "ts_updated",
                "ts_expires",
                "ts_load",
                "sk_core_credit_evaluation",
                "year",
                "month",
                "day",
            ]

            for col in expected_columns:
                assert col in columns, f"Column {col} missing from result"

    def test_business_logic_flags(
        self,
        spark_session,
        credit_evaluation_df,
        house_df,
        house_listing_relation_df,
        user_df,
        mock_configuration_service,
        mock_surrogate_keys_helper,
    ):
        """Test the business logic flags (is_early_credit, is_credit_passport, is_bypass)."""

        # Create a mock for spark.read
        mock_read = Mock()

        # Configure mock to return appropriate DataFrame based on table name
        def mock_table_side_effect(table_name):
            if table_name == "test.credit_evaluation":
                return credit_evaluation_df
            elif table_name == "test.house":
                return house_df
            elif table_name == "test.house_listing_relation":
                return house_listing_relation_df
            elif table_name == "test.user":
                return user_df
            else:
                raise ValueError(f"Unknown table: {table_name}")

        mock_read.table.side_effect = mock_table_side_effect

        with patch.object(
            type(spark_session), "read", new_callable=lambda: mock_read, create=True
        ):

            # Create job and run
            job = CoreCreditEvaluationSparkJob()
            args = Namespace(load_start_date=None, load_end_date=None)
            result_df = job.create_core_model(spark_session, args)

            result_data = result_df.collect()

            # Test case 1: Regular evaluation (has id_proposal and id_group) - positive result
            eval_1 = [row for row in result_data if row["id_credit_evaluation"] == 1][0]
            assert (
                eval_1["is_early_credit"] is False
            ), "Should not be early credit (has id_proposal and id_group)"
            assert (
                eval_1["is_credit_passport"] is False
            ), "Should not be credit passport (scope=HOUSE)"
            assert (
                eval_1["is_bypass"] is False
            ), "Should not be bypass (result=PRE_APPROVED_WITH_GUARANTEE)"
            assert (
                eval_1["reason"] is None
            ), "Should have NULL reason for positive result"
            assert (
                eval_1["result"] == "PRE_APPROVED_WITH_GUARANTEE"
            ), "Should have PRE_APPROVED_WITH_GUARANTEE result"

            # Test case 2: Early credit evaluation (NULL id_proposal and id_group) with negative result
            eval_2 = [row for row in result_data if row["id_credit_evaluation"] == 2][0]
            assert (
                eval_2["is_early_credit"] is True
            ), "Should be early credit (NULL id_proposal and id_group)"
            assert (
                eval_2["is_credit_passport"] is False
            ), "Should not be credit passport (scope=HOUSE)"
            assert (
                eval_2["is_bypass"] is False
            ), "Should not be bypass (result=PRE_REJECTED)"
            assert (
                eval_2["reason"] == "INSUFFICIENT_INCOME"
            ), "Should have INSUFFICIENT_INCOME reason for negative result"
            assert eval_2["result"] == "PRE_REJECTED", "Should have PRE_REJECTED result"

            # Test case 3: Credit passport with bypass - positive result
            eval_3 = [row for row in result_data if row["id_credit_evaluation"] == 3][0]
            assert (
                eval_3["is_early_credit"] is True
            ), "Should be early credit (NULL id_proposal and id_group)"
            assert (
                eval_3["is_credit_passport"] is True
            ), "Should be credit passport (scope=CITY)"
            assert eval_3["is_bypass"] is True, "Should be bypass (result=BYPASSED)"
            assert (
                eval_3["reason"] is None
            ), "Should have NULL reason for positive bypass"
            assert eval_3["result"] == "BYPASSED", "Should have BYPASSED result"

            # Test case 4: Regular evaluation with negative result
            eval_4 = [row for row in result_data if row["id_credit_evaluation"] == 4][0]
            assert (
                eval_4["reason"] == "BAD_SCORE"
            ), "Should have BAD_SCORE reason for negative result"
            assert (
                eval_4["result"] == "PRE_REJECTED"
            ), "Should have PRE_REJECTED result for negative case"

    def test_create_core_model_with_date_filtering(
        self,
        spark_session,
        credit_evaluation_df,
        house_df,
        house_listing_relation_df,
        user_df,
        mock_configuration_service,
        mock_surrogate_keys_helper,
    ):
        """Test create_core_model with date filtering for incremental loads."""

        # Create a mock for spark.read
        mock_read = Mock()

        # Mock filter to simulate date filtering
        def mock_filter(condition):
            # Simulate filtering by returning only records within date range
            # eval_4 has ts_updated = 2022-12-25 (before range) and should be excluded
            # evals 1, 2, 3 have ts_updated in 2025-01-01 to 2025-01-03 (within range)
            filtered_data = credit_evaluation_df.collect()
            filtered_data = [
                row for row in filtered_data if row["id"] != 4
            ]  # Exclude eval 4
            return spark_session.createDataFrame(
                filtered_data, credit_evaluation_df.schema
            )

        # Configure mock to return appropriate DataFrame based on table name
        def mock_table_side_effect(table_name):
            if table_name == "test.credit_evaluation":
                mock_table = Mock()
                mock_table.filter = mock_filter
                return mock_table
            elif table_name == "test.house":
                return house_df
            elif table_name == "test.house_listing_relation":
                return house_listing_relation_df
            elif table_name == "test.user":
                return user_df
            else:
                raise ValueError(f"Unknown table: {table_name}")

        mock_read.table.side_effect = mock_table_side_effect

        # Mock table reads with filtering
        with patch.object(
            type(spark_session), "read", new_callable=lambda: mock_read, create=True
        ):

            # Create job and run with date filtering
            job = CoreCreditEvaluationSparkJob()
            args = Namespace()
            args.load_start_date = "2025-01-01"
            args.load_end_date = "2025-01-31"

            result_df = job.create_core_model(spark_session, args)

            result_data = result_df.select(
                "id_credit_evaluation", "ts_updated"
            ).collect()

            # Check that only evaluations within the date range are included
            result_ids = [row["id_credit_evaluation"] for row in result_data]
            assert 1 in result_ids, "eval_1 should be included (within date range)"
            assert 2 in result_ids, "eval_2 should be included (within date range)"
            assert 3 in result_ids, "eval_3 should be included (within date range)"
            assert 4 not in result_ids, "eval_4 should be excluded (outside date range)"

    def test_load_credit_evaluation_data_method(
        self, spark_session, credit_evaluation_df, mock_configuration_service
    ):
        """Test _load_credit_evaluation_data method."""

        # Create a mock for spark.read
        mock_read = Mock()
        mock_read.table.return_value = credit_evaluation_df

        with patch.object(
            type(spark_session), "read", new_callable=lambda: mock_read, create=True
        ):

            job = CoreCreditEvaluationSparkJob()
            config = {"CREDIT_EVALUATION_TABLE": "test.credit_evaluation"}

            # Test without date filtering
            args = Namespace(load_start_date=None, load_end_date=None)
            result_df = job._load_credit_evaluation_data(spark_session, config, args)

            # Should call the correct table
            mock_read.table.assert_called_with("test.credit_evaluation")
            assert result_df is not None

    def test_get_credit_evaluation_config(
        self, spark_session, mock_configuration_service
    ):
        """Test get_credit_evaluation_config method."""

        job = CoreCreditEvaluationSparkJob()
        config = job.get_credit_evaluation_config()

        expected_keys = ["ENTITY_TYPE", "CREDIT_EVALUATION_TABLE"]

        for key in expected_keys:
            assert key in config, f"Config should contain {key}"

        assert config["ENTITY_TYPE"] == "CREDIT_EVALUATION"

    def test_scope_values_edge_cases(
        self,
        spark_session,
        house_df,
        house_listing_relation_df,
        user_df,
        mock_configuration_service,
        mock_surrogate_keys_helper,
    ):
        """Test edge cases for scope values in credit passport logic."""
        from pyspark.sql.types import (
            StructType,
            StructField,
            StringType,
            TimestampType,
            LongType,
            DoubleType,
            DecimalType,
        )
        from datetime import datetime
        from decimal import Decimal

        # Create edge case data with different scope values
        schema = StructType(
            [
                StructField("id", LongType(), True),
                StructField("id_house", LongType(), True),
                StructField("id_proposal", LongType(), True),
                StructField("id_user", LongType(), True),
                StructField("id_city", LongType(), True),
                StructField("id_group", LongType(), True),
                StructField("reason", StringType(), True),
                StructField("result", StringType(), True),
                StructField("early_result", StringType(), True),
                StructField("limit_value", DoubleType(), True),
                StructField("pre_approved_limit", DecimalType(10, 2), True),
                StructField("status", StringType(), True),
                StructField("type", StringType(), True),  # Source column name
                StructField("scope", StringType(), True),
                StructField("ts_created", TimestampType(), True),
                StructField("ts_updated", TimestampType(), True),
                StructField("ts_expires", TimestampType(), True),
            ]
        )

        edge_case_data = [
            # scope = CITY (credit passport)
            (
                1,
                1001,
                2001,
                3001,
                4001,
                5001,
                "REASON",
                "REGULAR",
                None,
                1000.0,  # limit_value (double)
                Decimal("1000.00"),  # pre_approved_limit
                "FINISHED",
                "REGULAR",
                "CITY",
                datetime(2025, 1, 1),
                datetime(2025, 1, 1),
                datetime(2025, 2, 1),
            ),
            # scope = HOUSE (not credit passport)
            (
                2,
                1002,
                2002,
                3002,
                4002,
                5002,
                "REASON",
                "REGULAR",
                None,
                1000.0,  # limit_value (double)
                Decimal("1000.00"),  # pre_approved_limit
                "FINISHED",
                "REGULAR",
                "HOUSE",
                datetime(2025, 1, 2),
                datetime(2025, 1, 2),
                datetime(2025, 2, 2),
            ),
            # scope = NULL (not credit passport)
            (
                3,
                1003,
                2003,
                3003,
                4003,
                5003,
                "REASON",
                "REGULAR",
                None,
                1000.0,  # limit_value (double)
                Decimal("1000.00"),  # pre_approved_limit
                "FINISHED",
                "REGULAR",
                None,
                datetime(2025, 1, 3),
                datetime(2025, 1, 3),
                datetime(2025, 2, 3),
            ),
        ]

        edge_case_df = spark_session.createDataFrame(edge_case_data, schema)

        # Mock spark.read
        mock_read = Mock()

        # Configure mock to return appropriate DataFrame based on table name
        def mock_table_side_effect(table_name):
            if table_name == "test.credit_evaluation":
                return edge_case_df
            elif table_name == "test.house":
                return house_df
            elif table_name == "test.house_listing_relation":
                return house_listing_relation_df
            elif table_name == "test.user":
                return user_df
            else:
                raise ValueError(f"Unknown table: {table_name}")

        mock_read.table.side_effect = mock_table_side_effect

        with patch.object(
            type(spark_session), "read", new_callable=lambda: mock_read, create=True
        ):

            job = CoreCreditEvaluationSparkJob()
            args = Namespace(load_start_date=None, load_end_date=None)
            result_df = job.create_core_model(spark_session, args)

            result_data = result_df.collect()

            # Check credit passport logic
            eval_1 = [row for row in result_data if row["id_credit_evaluation"] == 1][0]
            assert (
                eval_1["is_credit_passport"] is True
            ), "Should be credit passport (scope=CITY)"

            eval_2 = [row for row in result_data if row["id_credit_evaluation"] == 2][0]
            assert (
                eval_2["is_credit_passport"] is False
            ), "Should not be credit passport (scope=HOUSE)"

            eval_3 = [row for row in result_data if row["id_credit_evaluation"] == 3][0]
            assert (
                eval_3["is_credit_passport"] is False
            ), "Should not be credit passport (scope=NULL)"

    def test_result_values_edge_cases(
        self,
        spark_session,
        house_df,
        house_listing_relation_df,
        user_df,
        mock_configuration_service,
        mock_surrogate_keys_helper,
    ):
        """Test edge cases for result values in bypass logic."""
        from pyspark.sql.types import (
            StructType,
            StructField,
            StringType,
            TimestampType,
            LongType,
            DoubleType,
            DecimalType,
        )
        from datetime import datetime
        from decimal import Decimal

        # Create edge case data with different result values
        schema = StructType(
            [
                StructField("id", LongType(), True),
                StructField("id_house", LongType(), True),
                StructField("id_proposal", LongType(), True),
                StructField("id_user", LongType(), True),
                StructField("id_city", LongType(), True),
                StructField("id_group", LongType(), True),
                StructField("reason", StringType(), True),
                StructField("result", StringType(), True),
                StructField("early_result", StringType(), True),
                StructField("limit_value", DoubleType(), True),
                StructField("pre_approved_limit", DecimalType(10, 2), True),
                StructField("status", StringType(), True),
                StructField("type", StringType(), True),  # Source column name
                StructField("scope", StringType(), True),
                StructField("ts_created", TimestampType(), True),
                StructField("ts_updated", TimestampType(), True),
                StructField("ts_expires", TimestampType(), True),
            ]
        )

        edge_case_data = [
            # result = BYPASSED (is bypass)
            (
                1,
                1001,
                2001,
                3001,
                4001,
                5001,
                "REASON",
                "BYPASSED",
                None,
                1000.0,  # limit_value (double)
                Decimal("1000.00"),  # pre_approved_limit
                "FINISHED",
                "REGULAR",
                "HOUSE",
                datetime(2025, 1, 1),
                datetime(2025, 1, 1),
                datetime(2025, 2, 1),
            ),
            # result = PRE_APPROVED (not bypass)
            (
                2,
                1002,
                2002,
                3002,
                4002,
                5002,
                "REASON",
                "PRE_APPROVED",
                None,
                1000.0,  # limit_value (double)
                Decimal("1000.00"),  # pre_approved_limit
                "FINISHED",
                "REGULAR",
                "HOUSE",
                datetime(2025, 1, 2),
                datetime(2025, 1, 2),
                datetime(2025, 2, 2),
            ),
            # result = NULL (not bypass)
            (
                3,
                1003,
                2003,
                3003,
                4003,
                5003,
                "REASON",
                None,
                None,
                1000.0,  # limit_value (double)
                Decimal("1000.00"),  # pre_approved_limit
                "FINISHED",
                "REGULAR",
                "HOUSE",
                datetime(2025, 1, 3),
                datetime(2025, 1, 3),
                datetime(2025, 2, 3),
            ),
        ]

        edge_case_df = spark_session.createDataFrame(edge_case_data, schema)

        # Mock spark.read
        mock_read = Mock()

        # Configure mock to return appropriate DataFrame based on table name
        def mock_table_side_effect(table_name):
            if table_name == "test.credit_evaluation":
                return edge_case_df
            elif table_name == "test.house":
                return house_df
            elif table_name == "test.house_listing_relation":
                return house_listing_relation_df
            elif table_name == "test.user":
                return user_df
            else:
                raise ValueError(f"Unknown table: {table_name}")

        mock_read.table.side_effect = mock_table_side_effect

        with patch.object(
            type(spark_session), "read", new_callable=lambda: mock_read, create=True
        ):

            job = CoreCreditEvaluationSparkJob()
            args = Namespace(load_start_date=None, load_end_date=None)
            result_df = job.create_core_model(spark_session, args)

            result_data = result_df.collect()

            # Check bypass logic
            eval_1 = [row for row in result_data if row["id_credit_evaluation"] == 1][0]
            assert eval_1["is_bypass"] is True, "Should be bypass (result=BYPASSED)"

            eval_2 = [row for row in result_data if row["id_credit_evaluation"] == 2][0]
            assert (
                eval_2["is_bypass"] is False
            ), "Should not be bypass (result=PRE_APPROVED)"

            eval_3 = [row for row in result_data if row["id_credit_evaluation"] == 3][0]
            assert eval_3["is_bypass"] is False, "Should not be bypass (result=NULL)"

    def test_reason_and_result_values_comprehensive(
        self,
        spark_session,
        house_df,
        house_listing_relation_df,
        user_df,
        mock_configuration_service,
        mock_surrogate_keys_helper,
    ):
        """Test comprehensive reason and result values used in production."""
        from pyspark.sql.types import (
            StructType,
            StructField,
            StringType,
            TimestampType,
            LongType,
            DoubleType,
            DecimalType,
        )
        from datetime import datetime
        from decimal import Decimal

        # Create comprehensive test data with real reason and result values
        schema = StructType(
            [
                StructField("id", LongType(), True),
                StructField("id_house", LongType(), True),
                StructField("id_proposal", LongType(), True),
                StructField("id_user", LongType(), True),
                StructField("id_city", LongType(), True),
                StructField("id_group", LongType(), True),
                StructField("reason", StringType(), True),
                StructField("result", StringType(), True),
                StructField("early_result", StringType(), True),
                StructField("limit_value", DoubleType(), True),
                StructField("pre_approved_limit", DecimalType(10, 2), True),
                StructField("status", StringType(), True),
                StructField("type", StringType(), True),  # Source column name
                StructField("scope", StringType(), True),
                StructField("ts_created", TimestampType(), True),
                StructField("ts_updated", TimestampType(), True),
                StructField("ts_expires", TimestampType(), True),
            ]
        )

        comprehensive_data = [
            # Positive results with NULL reasons (no rejection reason needed)
            (
                1,
                1001,
                2001,
                3001,
                4001,
                5001,
                None,
                "REGULAR",
                None,
                2000.0,  # limit_value (double)
                Decimal("2000.00"),  # pre_approved_limit
                "FINISHED",
                "REGULAR",
                "HOUSE",
                datetime(2025, 1, 1),
                datetime(2025, 1, 1),
                datetime(2025, 2, 1),
            ),
            (
                2,
                1002,
                2002,
                3002,
                4002,
                5002,
                None,
                "PRE_APPROVED",
                None,
                2500.0,  # limit_value (double)
                Decimal("2500.00"),  # pre_approved_limit
                "FINISHED",
                "REGULAR",
                "HOUSE",
                datetime(2025, 1, 2),
                datetime(2025, 1, 2),
                datetime(2025, 2, 2),
            ),
            (
                3,
                1003,
                2003,
                3003,
                4003,
                5003,
                None,
                "PRE_APPROVED_WITH_GUARANTEE",
                None,
                3000.0,  # limit_value (double)
                Decimal("3000.00"),  # pre_approved_limit
                "FINISHED",
                "REGULAR",
                "HOUSE",
                datetime(2025, 1, 3),
                datetime(2025, 1, 3),
                datetime(2025, 2, 3),
            ),
            (
                4,
                1004,
                2004,
                3004,
                4004,
                5004,
                None,
                "BYPASSED",
                None,
                5000.0,  # limit_value (double)
                Decimal("5000.00"),  # pre_approved_limit
                "FINISHED",
                "REGULAR",
                "CITY",
                datetime(2025, 1, 4),
                datetime(2025, 1, 4),
                datetime(2025, 2, 4),
            ),
            # Negative results with specific rejection reasons
            (
                5,
                1005,
                2005,
                3005,
                4005,
                5005,
                "INSUFFICIENT_INCOME",
                "PRE_REJECTED",
                None,
                None,
                None,
                "FINISHED",
                "REGULAR",
                "HOUSE",
                datetime(2025, 1, 5),
                datetime(2025, 1, 5),
                datetime(2025, 2, 5),
            ),
            (
                6,
                1006,
                2006,
                3006,
                4006,
                5006,
                "BAD_SCORE",
                "PRE_REJECTED",
                None,
                None,
                None,
                "FINISHED",
                "REGULAR",
                "HOUSE",
                datetime(2025, 1, 6),
                datetime(2025, 1, 6),
                datetime(2025, 2, 6),
            ),
            (
                7,
                1007,
                2007,
                3007,
                4007,
                5007,
                "CLEAR_NO",
                "PRE_REJECTED",
                None,
                None,
                None,
                "FINISHED",
                "REGULAR",
                "HOUSE",
                datetime(2025, 1, 7),
                datetime(2025, 1, 7),
                datetime(2025, 2, 7),
            ),
            (
                8,
                1008,
                2008,
                3008,
                4008,
                5008,
                "HIGH_RISK_PROFILE",
                "PRE_REJECTED",
                None,
                None,
                None,
                "FINISHED",
                "REGULAR",
                "HOUSE",
                datetime(2025, 1, 8),
                datetime(2025, 1, 8),
                datetime(2025, 2, 8),
            ),
        ]

        comprehensive_df = spark_session.createDataFrame(comprehensive_data, schema)

        # Mock spark.read
        mock_read = Mock()

        # Configure mock to return appropriate DataFrame based on table name
        def mock_table_side_effect(table_name):
            if table_name == "test.credit_evaluation":
                return comprehensive_df
            elif table_name == "test.house":
                return house_df
            elif table_name == "test.house_listing_relation":
                return house_listing_relation_df
            elif table_name == "test.user":
                return user_df
            else:
                raise ValueError(f"Unknown table: {table_name}")

        mock_read.table.side_effect = mock_table_side_effect

        with patch.object(
            type(spark_session), "read", new_callable=lambda: mock_read, create=True
        ):

            job = CoreCreditEvaluationSparkJob()
            args = Namespace(load_start_date=None, load_end_date=None)
            result_df = job.create_core_model(spark_session, args)

            result_data = result_df.collect()

            # Test positive results
            positive_results = [
                "REGULAR",
                "PRE_APPROVED",
                "PRE_APPROVED_WITH_GUARANTEE",
                "BYPASSED",
            ]
            negative_results = ["PRE_REJECTED"]

            # Verify positive results have NULL reasons
            for eval_id in [1, 2, 3, 4]:
                eval_row = [
                    row for row in result_data if row["id_credit_evaluation"] == eval_id
                ][0]
                assert (
                    eval_row["result"] in positive_results
                ), f"Evaluation {eval_id} should have positive result"
                assert (
                    eval_row["reason"] is None
                ), f"Evaluation {eval_id} should have NULL reason for positive result"

            # Verify negative results have specific rejection reasons
            for eval_id in [5, 6, 7, 8]:
                eval_row = [
                    row for row in result_data if row["id_credit_evaluation"] == eval_id
                ][0]
                assert (
                    eval_row["result"] in negative_results
                ), f"Evaluation {eval_id} should have negative result"
                assert eval_row["reason"] in [
                    "INSUFFICIENT_INCOME",
                    "BAD_SCORE",
                    "CLEAR_NO",
                    "HIGH_RISK_PROFILE",
                ], f"Evaluation {eval_id} should have negative reason"

            # Test specific bypass case (positive with NULL reason)
            bypass_eval = [
                row for row in result_data if row["id_credit_evaluation"] == 4
            ][0]
            assert (
                bypass_eval["is_bypass"] is True
            ), "Should be bypass (result=BYPASSED)"
            assert (
                bypass_eval["is_credit_passport"] is True
            ), "Should be credit passport (scope=CITY)"
            assert (
                bypass_eval["reason"] is None
            ), "Bypassed evaluation should have NULL reason"

            # Test specific negative cases
            rejected_eval = [
                row for row in result_data if row["id_credit_evaluation"] == 5
            ][0]
            assert (
                rejected_eval["is_bypass"] is False
            ), "Should not be bypass (result=PRE_REJECTED)"
            assert (
                rejected_eval["result"] == "PRE_REJECTED"
            ), "Should have PRE_REJECTED result"
            assert (
                rejected_eval["reason"] == "INSUFFICIENT_INCOME"
            ), "Should have INSUFFICIENT_INCOME reason for rejection"
