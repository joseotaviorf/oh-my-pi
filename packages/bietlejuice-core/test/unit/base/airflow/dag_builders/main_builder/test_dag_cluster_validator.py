from contextlib import nullcontext as does_not_raise

import pytest


class TestDAGClusterValidator:
    @pytest.fixture
    def dag_cluster_validator(self):
        from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_cluster_validator import (
            DAGClusterValidator,
        )

        return DAGClusterValidator()

    @pytest.mark.parametrize(
        "dag_declaration, expectation",
        [
            (
                {
                    "cluster": {
                        "type": "any_cluster_type",
                        "access_control_list": {
                            "group_name": "admins",
                            "permission_level": "CAN_MANAGE",
                        },
                    },
                },
                does_not_raise(),
            ),
            (
                {
                    "cluster": {
                        "type": "any_cluster_type",
                        "access_control_list": [
                            {
                                "group_name": "admins",
                                "permission_level": "CAN_MANAGE",
                            },
                            {
                                "group_name": "analytics-engineers",
                                "permission_level": "CAN_ATTACH_TO",
                            },
                        ],
                    },
                },
                does_not_raise(),
            ),
            (
                {
                    "cluster": {
                        "type": "",
                        "access_control_list": {
                            "group_name": "",
                            "permission_level": "",
                        },
                    },
                },
                pytest.raises(AssertionError),
            ),
            (
                {"cluster": {}},
                pytest.raises(AssertionError),
            ),
            ({}, pytest.raises(AssertionError)),
        ],
    )
    def test_validate_cluster(
        self, dag_cluster_validator, dag_declaration, expectation
    ):
        with expectation:
            assert (
                dag_cluster_validator.validate_cluster(dag_declaration=dag_declaration)
                is None
            )


class TestEmrClusterConfiguration:
    @pytest.fixture
    def dag_cluster_validator(self):
        from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_cluster_validator import (
            DAGClusterValidator,
        )

        return DAGClusterValidator()

    def _base_declaration(self, cluster):
        return {"cluster": cluster}

    def test_emr_cluster_valid_task_split_passes(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {"instance_count": 2},
                    "task_nodes": {"instance_count": 3},
                },
            }
        )
        dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_cluster_core_task_nodes_with_types_passes(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {
                        "node_type_id": "m7g.2xlarge",
                        "instance_count": 1,
                    },
                    "task_nodes": {
                        "node_type_id": "m7g.xlarge",
                        "instance_count": 2,
                    },
                },
            }
        )
        dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_cluster_core_nodes_zero_instance_count_passes(
        self, dag_cluster_validator
    ):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_consolidation_m_general_single_node_cluster",
                "custom_configurations": {
                    "core_nodes": {"instance_count": 0},
                },
            }
        )
        dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_cluster_legacy_num_workers_split_still_passes(
        self, dag_cluster_validator
    ):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "num_workers": 5,
                    "num_task_workers": 3,
                },
            }
        )
        dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_cluster_custom_spark_version_valid_split_passes(
        self, dag_cluster_validator
    ):
        declaration = self._base_declaration(
            {
                "type": "custom_cluster",
                "custom_configurations": {
                    "spark_version": "emr-7.12.0",
                    "num_workers": 4,
                    "num_task_workers": 2,
                    "aws_attributes": {"task_availability": "ON_DEMAND"},
                },
            }
        )
        dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_cluster_num_task_workers_equals_num_workers_raises(
        self, dag_cluster_validator
    ):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "num_workers": 3,
                    "num_task_workers": 3,
                },
            }
        )
        with pytest.raises(AssertionError, match="must be less than"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_databricks_cluster_num_task_workers_raises(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "databricks_16_4_med_general_cluster",
                "custom_configurations": {"num_task_workers": 1},
            }
        )
        with pytest.raises(AssertionError, match="EMR-only cluster keys"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_databricks_cluster_task_availability_raises(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "databricks_16_4_med_general_cluster",
                "custom_configurations": {
                    "aws_attributes": {"task_availability": "SPOT"},
                },
            }
        )
        with pytest.raises(AssertionError, match="EMR-only cluster keys"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_cluster_invalid_task_availability_raises(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "num_workers": 3,
                    "num_task_workers": 1,
                    "aws_attributes": {"task_availability": "SPOT_WITH_FALLBACK"},
                },
            }
        )
        with pytest.raises(AssertionError, match="task_availability"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)


class TestEmrInstanceFleetConfiguration:
    @pytest.fixture
    def dag_cluster_validator(self):
        from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_cluster_validator import (
            DAGClusterValidator,
        )

        return DAGClusterValidator()

    def _base_declaration(self, cluster):
        return {"cluster": cluster}

    def test_emr_cluster_fleet_core_and_task_passes(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {
                        "target_on_demand": 2,
                        "target_spot": 8,
                        "allocation_strategy": "price-capacity-optimized",
                        "instance_types": ["m6i.4xlarge", "m6a.4xlarge"],
                        "bid_price_percentage": 100,
                    },
                    "task_nodes": {
                        "target_spot": 20,
                        "instance_types": ["m6i.4xlarge"],
                    },
                },
            }
        )
        dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_cluster_fleet_core_only_passes(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {
                        "target_on_demand": 2,
                        "instance_types": ["m6i.4xlarge"],
                    },
                },
            }
        )
        dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_fleet_missing_instance_types_raises(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {"target_on_demand": 1, "instance_types": []}
                },
            }
        )
        with pytest.raises(AssertionError, match="instance_types"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_fleet_zero_targets_raises(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {
                        "instance_types": ["m6i.4xlarge"],
                        "target_on_demand": 0,
                        "target_spot": 0,
                    },
                },
            }
        )
        with pytest.raises(AssertionError, match="target_on_demand"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_fleet_invalid_allocation_strategy_raises(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {
                        "target_spot": 1,
                        "instance_types": ["m6i.4xlarge"],
                        "allocation_strategy": "not-a-real-strategy",
                    },
                },
            }
        )
        with pytest.raises(AssertionError, match="allocation_strategy"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_fleet_invalid_bid_price_percentage_raises(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {
                        "target_on_demand": 1,
                        "instance_types": ["m6i.4xlarge"],
                        "bid_price_percentage": -10,
                    },
                },
            }
        )
        with pytest.raises(AssertionError, match="bid_price_percentage"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_fleet_invalid_spot_timeout_minutes_raises(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {
                        "target_spot": 1,
                        "instance_types": ["m6i.4xlarge"],
                        "spot_timeout_minutes": 3,
                    },
                },
            }
        )
        with pytest.raises(AssertionError, match="spot_timeout_minutes"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_fleet_mixed_keys_in_one_block_raises(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {
                        "node_type_id": "m5.xlarge",
                        "instance_types": ["m6i.4xlarge"],
                        "target_on_demand": 1,
                    },
                },
            }
        )
        with pytest.raises(AssertionError, match="mixes instance-group keys"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_core_group_task_fleet_mismatch_raises(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {"node_type_id": "m5.xlarge", "instance_count": 2},
                    "task_nodes": {"target_spot": 5, "instance_types": ["m6i.4xlarge"]},
                },
            }
        )
        with pytest.raises(AssertionError, match="must both use instance groups"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_fleet_task_availability_raises(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {
                        "target_on_demand": 1,
                        "instance_types": ["m6i.4xlarge"],
                    },
                    "task_nodes": {"target_spot": 5, "instance_types": ["m6i.4xlarge"]},
                    "aws_attributes": {"task_availability": "SPOT"},
                },
            }
        )
        with pytest.raises(AssertionError, match="task_availability"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_fleet_task_without_core_nodes_raises(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "task_nodes": {"target_spot": 5, "instance_types": ["m6i.4xlarge"]},
                },
            }
        )
        with pytest.raises(AssertionError, match="TASK capacity"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_fleet_max_nodes_partial_override_passes(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {"max_nodes": 6},
                },
            }
        )
        dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_fleet_core_zero_targets_with_max_nodes_raises(
        self, dag_cluster_validator
    ):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {
                        "target_on_demand": 0,
                        "target_spot": 0,
                        "max_nodes": 6,
                        "instance_types": ["m6i.4xlarge"],
                    },
                },
            }
        )
        with pytest.raises(AssertionError, match="core to scale from zero"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_fleet_task_zero_targets_with_max_nodes_passes(
        self, dag_cluster_validator
    ):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {
                        "target_on_demand": 2,
                        "instance_types": ["m6i.4xlarge"],
                    },
                    "task_nodes": {
                        "target_on_demand": 0,
                        "target_spot": 0,
                        "max_nodes": 12,
                        "instance_types": ["m6i.4xlarge"],
                    },
                },
            }
        )
        dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_fleet_max_nodes_below_targets_raises(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {
                        "target_on_demand": 4,
                        "instance_types": ["m6i.4xlarge"],
                        "max_nodes": 2,
                    },
                },
            }
        )
        with pytest.raises(AssertionError, match="max_nodes"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_fleet_max_nodes_mixed_with_instance_count_raises(
        self, dag_cluster_validator
    ):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {
                        "instance_count": 2,
                        "max_nodes": 6,
                        "node_type_id": "m5.xlarge",
                    },
                },
            }
        )
        with pytest.raises(AssertionError, match="mixes instance-group keys"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    @pytest.mark.parametrize(
        "invalid_max_nodes",
        ["6", 6.5, True],
    )
    def test_emr_fleet_max_nodes_non_integer_raises(
        self, dag_cluster_validator, invalid_max_nodes
    ):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {"max_nodes": invalid_max_nodes},
                },
            }
        )
        with pytest.raises(AssertionError, match="max_nodes"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    @pytest.mark.parametrize(
        "legacy_key, legacy_value",
        [
            ("node_type_id", "m5a.large"),
            ("num_workers", 2),
            ("num_task_workers", 1),
            ("task_node_type_id", "m5a.large"),
        ],
    )
    def test_emr_fleet_legacy_scalar_keys_raise(
        self, dag_cluster_validator, legacy_key, legacy_value
    ):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "core_nodes": {
                        "target_on_demand": 1,
                        "instance_types": ["m6i.4xlarge"],
                    },
                    legacy_key: legacy_value,
                },
            }
        )
        with pytest.raises(AssertionError, match="Legacy instance-group keys"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)
