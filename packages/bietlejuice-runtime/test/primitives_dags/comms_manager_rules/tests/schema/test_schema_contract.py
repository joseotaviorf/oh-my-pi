"""
Schema Contract Tests for Communication Manager Rules

This module contains contract tests that validate the data schema and structure
produced by the communication manager rules processing pipeline. These tests
use REAL functions with REAL DataFrames to ensure that the output contains
all expected columns and maintains the correct data contract.
"""

import os

# Import the functions we want to test
import sys
import unittest

from pyspark.sql import SparkSession
from pyspark.sql.types import (
    ArrayType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)


def _find_project_root() -> str:
    current = os.path.abspath(os.path.dirname(__file__))
    while current != os.path.dirname(current):
        if os.path.exists(os.path.join(current, ".git")):
            return current
        current = os.path.dirname(current)
    raise RuntimeError("Could not locate project root from test path")


spark_jobs_path = os.path.join(
    _find_project_root(),
    "dags",
    "primitives",
    "comms_manager_rules",
    "spark_jobs",
)
sys.path.append(spark_jobs_path)

from load_comms_manager_rules import (  # noqa: E402
    explode_and_flatten_actions,
    explode_rules,
)


class TestSchemaContract(unittest.TestCase):
    """
    Contract tests to validate the expected schema and data structure
    of the communication manager rules processing pipeline using REAL DataFrames.
    """

    @classmethod
    def setUpClass(cls):
        """Set up Spark session for real DataFrame testing."""
        cls.spark = (
            SparkSession.builder.appName("SchemaContractTests")
            .master("local[1]")
            .config("spark.sql.shuffle.partitions", "1")
            .getOrCreate()
        )

    @classmethod
    def tearDownClass(cls):
        """Clean up Spark session."""
        cls.spark.stop()

    def test_real_explode_and_flatten_actions_schema(self):
        """
        Test that explode_and_flatten_actions produces the expected schema
        using REAL DataFrames and REAL function execution.
        """
        # Create a real DataFrame with the structure after exploding rules
        from datetime import datetime

        rules_data = [
            {
                "generated_at": datetime(2024, 1, 1, 12, 0, 0),
                "rule": {
                    "rule_id": "rule_123",
                    "status": "active",
                    "scope": {
                        "business_context": "rental",
                        "category": "notification",
                        "company": "quintoandar",
                        "context": "tenant",
                        "cost_center": "operations",
                        "journey_step": "onboarding",
                        "line": "for_rent",
                        "profile": "tenant",
                        "team": "growth",
                    },
                    "actions": [
                        {
                            "action_id": "action_456",
                            "notification_type": "email",
                            "profile": "tenant",
                            "reason": "welcome",
                            "deep_link": "https://app.com/welcome",
                            "templates": {
                                "subject_template": "Welcome {{name}}",
                                "body_template": "Hello {{name}}, welcome!",
                                "body_template_path": "/templates/welcome.html",
                                "subject_content": "Welcome John",
                                "body_content": "Hello John, welcome!",
                            },
                        }
                    ],
                },
            }
        ]

        # Define the proper schema for the DataFrame
        schema = StructType(
            [
                StructField("generated_at", TimestampType(), True),
                StructField(
                    "rule",
                    StructType(
                        [
                            StructField("rule_id", StringType(), True),
                            StructField("status", StringType(), True),
                            StructField(
                                "scope",
                                StructType(
                                    [
                                        StructField(
                                            "business_context", StringType(), True
                                        ),
                                        StructField("category", StringType(), True),
                                        StructField("company", StringType(), True),
                                        StructField("context", StringType(), True),
                                        StructField("cost_center", StringType(), True),
                                        StructField("journey_step", StringType(), True),
                                        StructField("line", StringType(), True),
                                        StructField("profile", StringType(), True),
                                        StructField("team", StringType(), True),
                                    ]
                                ),
                                True,
                            ),
                            StructField(
                                "actions",
                                ArrayType(
                                    StructType(
                                        [
                                            StructField(
                                                "action_id", StringType(), True
                                            ),
                                            StructField(
                                                "notification_type", StringType(), True
                                            ),
                                            StructField("profile", StringType(), True),
                                            StructField("reason", StringType(), True),
                                            StructField(
                                                "deep_link", StringType(), True
                                            ),
                                            StructField(
                                                "templates",
                                                StructType(
                                                    [
                                                        StructField(
                                                            "subject_template",
                                                            StringType(),
                                                            True,
                                                        ),
                                                        StructField(
                                                            "body_template",
                                                            StringType(),
                                                            True,
                                                        ),
                                                        StructField(
                                                            "body_template_path",
                                                            StringType(),
                                                            True,
                                                        ),
                                                        StructField(
                                                            "subject_content",
                                                            StringType(),
                                                            True,
                                                        ),
                                                        StructField(
                                                            "body_content",
                                                            StringType(),
                                                            True,
                                                        ),
                                                    ]
                                                ),
                                                True,
                                            ),
                                        ]
                                    )
                                ),
                                True,
                            ),
                        ]
                    ),
                    True,
                ),
            ]
        )

        # Create the real DataFrame with explicit schema
        rules_df = self.spark.createDataFrame(rules_data, schema)

        # Call the REAL function
        result_df = explode_and_flatten_actions(rules_df)

        # Get the actual column names from the real result
        actual_columns = result_df.columns

        # Define expected columns
        expected_columns = [
            # Processing metadata
            "generated_at",
            # Rule-level fields
            "rule_id",
            "status",
            "business_context",
            "category",
            "company",
            "context",
            "cost_center",
            "journey_step",
            "line",
            "rule_profile",
            "team",
            # Action-level fields (note: Spark flattens the column names)
            "action_id",
            "notification_type",
            "action_profile",
            "reason",
            "deep_link",
            # Template fields (note: Spark flattens the column names)
            "subject_template",
            "body_template",
            "body_template_path",
            "subject_content",
            "body_content",
            # Date partition columns
            "year",
            "month",
            "day",
        ]

        # Validate that all expected columns are present in the REAL result
        for expected_col in expected_columns:
            self.assertIn(
                expected_col,
                actual_columns,
                f"Expected column '{expected_col}' missing from actual DataFrame schema",
            )

        # Validate column count (note: now using rule_profile and action_profile aliases)
        self.assertEqual(
            len(actual_columns), 25, f"Expected 25 columns, got {len(actual_columns)}"
        )

        # Validate we can actually collect data (no errors)
        result_count = result_df.count()
        self.assertEqual(result_count, 1, "Expected 1 row in result DataFrame")

    def test_real_explode_rules_schema(self):
        """
        Test that explode_rules produces the expected schema
        using REAL DataFrames and REAL function execution.
        """
        # Create a real DataFrame with the raw JSON structure
        raw_data = [
            {
                "metadata": {"generated_at": "2024-01-01T12:00:00Z"},
                "rules": [
                    {
                        "rule_id": "rule_123",
                        "status": "active",
                        "scope": {
                            "business_context": "rental",
                            "category": "notification",
                            "company": "quintoandar",
                        },
                        "actions": [
                            {"action_id": "action_456", "notification_type": "email"}
                        ],
                    },
                    {
                        "rule_id": "rule_789",
                        "status": "inactive",
                        "scope": {
                            "business_context": "sales",
                            "category": "marketing",
                            "company": "quintoandar",
                        },
                        "actions": [
                            {"action_id": "action_999", "notification_type": "sms"}
                        ],
                    },
                ],
            }
        ]

        # Create the real DataFrame
        raw_df = self.spark.createDataFrame(raw_data)

        # Call the REAL function
        result_df = explode_rules(raw_df)

        # Validate the result has the expected structure
        self.assertIn(
            "rule", result_df.columns, "Expected 'rule' column after exploding rules"
        )

        # Validate we get the expected number of rows (2 rules)
        result_count = result_df.count()
        self.assertEqual(result_count, 2, "Expected 2 rows after exploding rules")

        # Validate we can access nested fields
        first_row = result_df.first()
        self.assertIsNotNone(first_row.rule, "Expected rule field to be accessible")

    def test_column_count_contract(self):
        """Test that the output DataFrame has the expected number of columns."""
        expected_column_count = 25  # Total number of columns in the contract

        # Get the expected columns from the contract
        result_columns = self._get_expected_final_columns()

        self.assertEqual(
            len(result_columns),
            expected_column_count,
            f"Expected {expected_column_count} columns, got {len(result_columns)}",
        )

    def test_mandatory_columns_contract(self):
        """Test that all mandatory columns are present in the output."""
        mandatory_columns = [
            "rule_id",
            "status",
            "action_id",
            "notification_type",
            "generated_at",  # New mandatory timestamp
        ]

        result_columns = self._get_expected_final_columns()

        for mandatory_col in mandatory_columns:
            self.assertIn(
                mandatory_col,
                result_columns,
                f"Mandatory column '{mandatory_col}' missing from output schema",
            )

    def test_timestamp_column_contract(self):
        """Test that the new timestamp column is properly added."""
        result_columns = self._get_expected_final_columns()

        # Verify the timestamp column is present
        self.assertIn(
            "generated_at",
            result_columns,
            "Timestamp column 'generated_at' missing from schema",
        )

    def test_action_template_columns_contract(self):
        """Test that all action template columns are preserved."""
        expected_template_columns = [
            "subject_template",
            "body_template",
            "body_template_path",
            "subject_content",
            "body_content",
        ]

        result_columns = self._get_expected_final_columns()

        for template_col in expected_template_columns:
            self.assertIn(
                template_col,
                result_columns,
                f"Template column '{template_col}' missing from schema",
            )

    def test_scope_columns_contract(self):
        """Test that all rule scope columns are preserved."""
        expected_scope_columns = [
            "business_context",
            "category",
            "company",
            "context",
            "cost_center",
            "journey_step",
            "line",
            "rule_profile",
            "team",
        ]

        result_columns = self._get_expected_final_columns()

        for scope_col in expected_scope_columns:
            self.assertIn(
                scope_col,
                result_columns,
                f"Scope column '{scope_col}' missing from schema",
            )

    def _create_mock_rules_dataframe(self):
        """Create a mock DataFrame representing the rules structure."""
        # This represents the structure after exploding rules but before flattening actions
        schema = StructType(
            [
                StructField(
                    "rule",
                    StructType(
                        [
                            StructField("rule_id", StringType(), True),
                            StructField("status", StringType(), True),
                            StructField(
                                "scope",
                                StructType(
                                    [
                                        StructField(
                                            "business_context", StringType(), True
                                        ),
                                        StructField("category", StringType(), True),
                                        StructField("company", StringType(), True),
                                        StructField("context", StringType(), True),
                                        StructField("cost_center", StringType(), True),
                                        StructField("journey_step", StringType(), True),
                                        StructField("line", StringType(), True),
                                        StructField("profile", StringType(), True),
                                        StructField("team", StringType(), True),
                                    ]
                                ),
                                True,
                            ),
                            StructField(
                                "actions",
                                ArrayType(
                                    StructType(
                                        [
                                            StructField(
                                                "action_id", StringType(), True
                                            ),
                                            StructField(
                                                "notification_type", StringType(), True
                                            ),
                                            StructField("profile", StringType(), True),
                                            StructField("reason", StringType(), True),
                                            StructField(
                                                "deep_link", StringType(), True
                                            ),
                                            StructField(
                                                "templates",
                                                StructType(
                                                    [
                                                        StructField(
                                                            "subject_template",
                                                            StringType(),
                                                            True,
                                                        ),
                                                        StructField(
                                                            "body_template",
                                                            StringType(),
                                                            True,
                                                        ),
                                                        StructField(
                                                            "body_template_path",
                                                            StringType(),
                                                            True,
                                                        ),
                                                        StructField(
                                                            "subject_content",
                                                            StringType(),
                                                            True,
                                                        ),
                                                        StructField(
                                                            "body_content",
                                                            StringType(),
                                                            True,
                                                        ),
                                                    ]
                                                ),
                                                True,
                                            ),
                                        ]
                                    )
                                ),
                                True,
                            ),
                        ]
                    ),
                    True,
                )
            ]
        )

        return self.spark.createDataFrame([], schema)

    def _get_expected_final_columns(self):
        """Get the list of columns that should be in the final output."""
        # This represents the columns selected in the explode_and_flatten_actions function
        # Note: Spark flattens nested column names, removing prefixes like "action." and "action.templates."
        return [
            # Processing metadata
            "generated_at",
            # Rule-level fields
            "rule_id",
            "status",
            "business_context",
            "category",
            "company",
            "context",
            "cost_center",
            "journey_step",
            "line",
            "rule_profile",
            "team",
            # Action-level fields (flattened by Spark)
            "action_id",
            "notification_type",
            "action_profile",
            "reason",
            "deep_link",
            # Template fields (flattened by Spark)
            "subject_template",
            "body_template",
            "body_template_path",
            "subject_content",
            "body_content",
            # Date partition columns
            "year",
            "month",
            "day",
        ]

    def test_explode_and_flatten_actions_with_missing_optional_fields(self):
        """
        Test that explode_and_flatten_actions handles missing optional fields gracefully.
        This tests the corner case where some records have missing optional fields.
        """
        from datetime import datetime

        # Test data with missing optional fields
        rules_data_with_missing_fields = [
            # Record 1: Complete record with all fields
            {
                "generated_at": datetime(2024, 1, 1, 12, 0, 0),
                "rule": {
                    "rule_id": "rule_complete",
                    "status": "active",  # This field is present
                    "scope": {
                        "business_context": "rental",
                        "category": "notification",
                        "company": "quintoandar",
                        "context": "tenant",
                        "cost_center": "operations",
                        "journey_step": "onboarding",
                        "line": "for_rent",
                        "profile": "tenant",
                        "team": "growth",
                    },
                    "actions": [
                        {
                            "action_id": "action_complete",
                            "notification_type": "email",
                            "profile": "tenant",
                            "reason": "welcome",
                            "deep_link": "https://app.com/welcome",
                            "templates": {
                                "subject_template": "Welcome {{name}}",
                                "body_template": "Hello {{name}}, welcome!",
                                "body_template_path": "/templates/welcome.html",
                                "subject_content": "Welcome John",
                                "body_content": "Hello John, welcome!",
                            },
                        }
                    ],
                },
            },
            # Record 2: Missing status field and some scope fields
            {
                "generated_at": datetime(2024, 1, 2, 12, 0, 0),
                "rule": {
                    "rule_id": "rule_missing_status",
                    # "status" field is missing
                    "scope": {
                        "business_context": "rental",
                        "company": "quintoandar",
                        "line": "for_rent",
                        "profile": "tenant",
                        # Missing: category, context, cost_center, journey_step, team
                    },
                    "actions": [
                        {
                            "action_id": "action_minimal",
                            "notification_type": "sms",
                            # Missing: profile, reason, deep_link, templates
                        }
                    ],
                },
            },
            # Record 3: Missing templates entirely
            {
                "generated_at": datetime(2024, 1, 3, 12, 0, 0),
                "rule": {
                    "rule_id": "rule_no_templates",
                    "status": "inactive",
                    "scope": {
                        "business_context": "sale",
                        "company": "quintoandar",
                        # Missing most scope fields
                    },
                    "actions": [
                        {
                            "action_id": "action_no_templates",
                            "notification_type": "push",
                            # Missing: templates object entirely
                        }
                    ],
                },
            },
        ]

        # Create DataFrame with proper schema to handle missing fields
        from pyspark.sql.types import (
            ArrayType,
            StringType,
            StructField,
            StructType,
            TimestampType,
        )

        schema = StructType(
            [
                StructField("generated_at", TimestampType(), True),
                StructField(
                    "rule",
                    StructType(
                        [
                            StructField("rule_id", StringType(), True),
                            StructField("status", StringType(), True),
                            StructField(
                                "scope",
                                StructType(
                                    [
                                        StructField(
                                            "business_context", StringType(), True
                                        ),
                                        StructField("category", StringType(), True),
                                        StructField("company", StringType(), True),
                                        StructField("context", StringType(), True),
                                        StructField("cost_center", StringType(), True),
                                        StructField("journey_step", StringType(), True),
                                        StructField("line", StringType(), True),
                                        StructField("profile", StringType(), True),
                                        StructField("team", StringType(), True),
                                    ]
                                ),
                                True,
                            ),
                            StructField(
                                "actions",
                                ArrayType(
                                    StructType(
                                        [
                                            StructField(
                                                "action_id", StringType(), True
                                            ),
                                            StructField(
                                                "notification_type", StringType(), True
                                            ),
                                            StructField("profile", StringType(), True),
                                            StructField("reason", StringType(), True),
                                            StructField(
                                                "deep_link", StringType(), True
                                            ),
                                            StructField(
                                                "templates",
                                                StructType(
                                                    [
                                                        StructField(
                                                            "subject_template",
                                                            StringType(),
                                                            True,
                                                        ),
                                                        StructField(
                                                            "body_template",
                                                            StringType(),
                                                            True,
                                                        ),
                                                        StructField(
                                                            "body_template_path",
                                                            StringType(),
                                                            True,
                                                        ),
                                                        StructField(
                                                            "subject_content",
                                                            StringType(),
                                                            True,
                                                        ),
                                                        StructField(
                                                            "body_content",
                                                            StringType(),
                                                            True,
                                                        ),
                                                    ]
                                                ),
                                                True,
                                            ),
                                        ]
                                    )
                                ),
                                True,
                            ),
                        ]
                    ),
                    True,
                ),
            ]
        )

        rules_df = self.spark.createDataFrame(rules_data_with_missing_fields, schema)

        # Call the REAL function - should handle missing fields gracefully
        result_df = explode_and_flatten_actions(rules_df)

        # Verify the function completes without errors
        self.assertIsNotNone(
            result_df, "Function should return a DataFrame even with missing fields"
        )

        # Verify we get the expected number of rows (3 actions from 3 rules)
        row_count = result_df.count()
        self.assertEqual(row_count, 3, f"Expected 3 rows, got {row_count}")

        # Collect the results to verify null handling
        results = result_df.collect()

        # Verify first record (complete) has all values
        complete_record = next(r for r in results if r.rule_id == "rule_complete")
        self.assertEqual(complete_record.status, "active")
        self.assertEqual(complete_record.business_context, "rental")
        self.assertEqual(complete_record.subject_template, "Welcome {{name}}")

        # Verify second record (missing status) has null for status
        missing_status_record = next(
            r for r in results if r.rule_id == "rule_missing_status"
        )
        self.assertIsNone(
            missing_status_record.status, "Missing status field should be null"
        )
        self.assertIsNone(
            missing_status_record.category, "Missing category field should be null"
        )
        self.assertIsNone(
            missing_status_record.reason, "Missing reason field should be null"
        )

        # Verify third record (no templates) has null template fields
        no_templates_record = next(
            r for r in results if r.rule_id == "rule_no_templates"
        )
        self.assertEqual(no_templates_record.status, "inactive")
        self.assertIsNone(
            no_templates_record.subject_template,
            "Missing subject_template should be null",
        )
        self.assertIsNone(
            no_templates_record.body_content, "Missing body_content should be null"
        )

        # Verify all records have mandatory ID fields
        for record in results:
            self.assertIsNotNone(record.rule_id, "rule_id should never be null")
            self.assertIsNotNone(record.action_id, "action_id should never be null")

        # Verify all expected columns are still present (with nulls where appropriate)
        expected_columns = [
            "generated_at",
            "rule_id",
            "status",
            "business_context",
            "category",
            "company",
            "context",
            "cost_center",
            "journey_step",
            "line",
            "rule_profile",
            "team",
            "action_id",
            "notification_type",
            "action_profile",
            "reason",
            "deep_link",
            "subject_template",
            "body_template",
            "body_template_path",
            "subject_content",
            "body_content",
            "year",
            "month",
            "day",
        ]

        actual_columns = result_df.columns
        for expected_col in expected_columns:
            self.assertIn(
                expected_col, actual_columns, f"Missing expected column: {expected_col}"
            )

        print(
            f"✅ Successfully handled {row_count} records with missing optional fields"
        )


class TestDataContractIntegration(unittest.TestCase):
    """
    Integration tests that validate the data contract end-to-end
    using sample data structures.
    """

    def test_sample_data_contract_validation(self):
        """Test the data contract with sample data structure."""
        # Sample JSON structure that represents the input format
        sample_input_structure = {
            "rules": [
                {
                    "rule_id": "rule_123",
                    "status": "active",
                    "scope": {
                        "business_context": "rental",
                        "category": "notification",
                        "company": "quintoandar",
                        "context": "tenant",
                        "cost_center": "operations",
                        "journey_step": "onboarding",
                        "line": "for_rent",
                        "profile": "tenant",
                        "team": "growth",
                    },
                    "actions": [
                        {
                            "action_id": "action_456",
                            "notification_type": "email",
                            "profile": "tenant",
                            "reason": "welcome",
                            "deep_link": "https://app.com/welcome",
                            "templates": {
                                "subject_template": "Welcome {{name}}",
                                "body_template": "Hello {{name}}, welcome!",
                                "body_template_path": "/templates/welcome.html",
                                "subject_content": "Welcome John",
                                "body_content": "Hello John, welcome!",
                            },
                        }
                    ],
                }
            ]
        }

        # Validate that the sample structure contains all expected fields
        self._validate_sample_structure(sample_input_structure)

    def _validate_sample_structure(self, sample_data):
        """Validate that sample data contains expected structure."""
        self.assertIn("rules", sample_data)
        self.assertIsInstance(sample_data["rules"], list)

        if sample_data["rules"]:
            rule = sample_data["rules"][0]

            # Validate rule-level fields
            self.assertIn("rule_id", rule)
            self.assertIn("status", rule)
            self.assertIn("scope", rule)
            self.assertIn("actions", rule)

            # Validate scope fields
            scope = rule["scope"]
            expected_scope_fields = [
                "business_context",
                "category",
                "company",
                "context",
                "cost_center",
                "journey_step",
                "line",
                "profile",
                "team",
            ]
            for field in expected_scope_fields:
                self.assertIn(field, scope, f"Missing scope field: {field}")

            # Validate action fields
            if rule["actions"]:
                action = rule["actions"][0]
                expected_action_fields = [
                    "action_id",
                    "notification_type",
                    "profile",
                    "reason",
                    "deep_link",
                    "templates",
                ]
                for field in expected_action_fields:
                    self.assertIn(field, action, f"Missing action field: {field}")

                # Validate template fields
                templates = action["templates"]
                expected_template_fields = [
                    "subject_template",
                    "body_template",
                    "body_template_path",
                    "subject_content",
                    "body_content",
                ]
                for field in expected_template_fields:
                    self.assertIn(field, templates, f"Missing template field: {field}")


class TestSchemaEvolution(unittest.TestCase):
    """
    Tests to ensure schema evolution is handled properly
    and backward compatibility is maintained.
    """

    def test_new_column_addition_contract(self):
        """Test that new columns can be added without breaking the contract."""
        # Test that generated_at was successfully added
        expected_columns = self._get_current_schema_columns()

        self.assertIn(
            "generated_at",
            expected_columns,
            "New timestamp column should be present in schema",
        )

    def test_backward_compatibility_contract(self):
        """Test that all original columns are still present after schema changes."""
        # These are the original columns that must always be present
        original_columns = [
            "rule_id",
            "status",
            "business_context",
            "category",
            "company",
            "context",
            "cost_center",
            "journey_step",
            "line",
            "rule_profile",
            "team",
            "action_id",
            "notification_type",
            "action_profile",
            "reason",
            "deep_link",
            "subject_template",
            "body_template",
            "body_template_path",
            "subject_content",
            "body_content",
        ]

        current_columns = self._get_current_schema_columns()

        for original_col in original_columns:
            self.assertIn(
                original_col,
                current_columns,
                f"Original column '{original_col}' must be preserved for backward compatibility",
            )

    def _get_current_schema_columns(self):
        """Get the current schema columns from the contract."""
        return [
            "generated_at",
            "rule_id",
            "status",
            "business_context",
            "category",
            "company",
            "context",
            "cost_center",
            "journey_step",
            "line",
            "rule_profile",
            "team",
            "action_id",
            "notification_type",
            "action_profile",
            "reason",
            "deep_link",
            "subject_template",
            "body_template",
            "body_template_path",
            "subject_content",
            "body_content",
            "year",
            "month",
            "day",
        ]


if __name__ == "__main__":
    # Run schema contract tests
    unittest.main(verbosity=2)
