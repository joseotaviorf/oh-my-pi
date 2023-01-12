from contextlib import nullcontext as does_not_raise

import pytest


class TestDAGDeclarationValidator:
    @pytest.mark.parametrize(
        "dag_declaration, expectation",
        [
            # minimum required fields
            (
                {
                    "workflow": {"type": "query", "layer": "dw"},
                    "dag": {"name": "any_dag_name", "owner": "Data Engineering"},
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
                    "workflow": {"type": "", "layer": ""},
                    "dag": {"name": "", "owner": ""},
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
                {
                    "workflow": {},
                    "dag": {"name": "any_dag_name", "owner": "Data Engineering"},
                    "cluster": {
                        "type": "any_cluster_type",
                        "access_control_list": {
                            "group_name": "admins",
                            "permission_level": "CAN_MANAGE",
                        },
                    },
                },
                pytest.raises(AssertionError),
            ),
            (
                {
                    "workflow": {"type": "query", "layer": "dw"},
                    "dag": {},
                    "cluster": {
                        "type": "any_cluster_type",
                        "access_control_list": {
                            "group_name": "admins",
                            "permission_level": "CAN_MANAGE",
                        },
                    },
                },
                pytest.raises(AssertionError),
            ),
            (
                {
                    "workflow": {"type": "query", "layer": "dw"},
                    "dag": {"name": "any_dag_name", "owner": "Data Engineering"},
                    "cluster": {},
                },
                pytest.raises(AssertionError),
            ),
            ({"workflow": {}, "dag": {}, "cluster": {}}, pytest.raises(AssertionError)),
        ],
    )
    def test_validate(self, dag_declaration_validator, dag_declaration, expectation):

        # act & assert
        with expectation:
            assert (
                dag_declaration_validator.validate(dag_declaration=dag_declaration)
                is None
            )
