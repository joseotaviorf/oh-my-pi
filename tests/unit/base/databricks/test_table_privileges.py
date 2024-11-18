import os
import unittest
from unittest.mock import patch
from bietlejuice.base.databricks.table_privilege_type_enum import TablePrivilegeTypeEnum
from bietlejuice.base.databricks.table_privileges import TablePrivileges


class TestTablePrivileges(unittest.TestCase):
    @patch("bietlejuice.base.databricks.table_privileges.UnityCatalogHelper")
    def test_apply(self, mock_unity_catalog_helper):
        # arrange
        table_name = "table_name"
        permissions_by_principal = {
            "principal1": [TablePrivilegeTypeEnum.SELECT],
            "principal2": [
                TablePrivilegeTypeEnum.SELECT,
                TablePrivilegeTypeEnum.APPLY_TAG,
            ],
        }
        catalog = "catalog"

        table_privileges = TablePrivileges(
            table_name, permissions_by_principal, catalog
        )

        # act
        table_privileges.apply()

        # assert
        mock_unity_catalog_helper.grant_table_permission.has_calls(
            [
                unittest.mock.call(
                    TablePrivilegeTypeEnum.SELECT, table_name, "principal1", catalog
                ),
                unittest.mock.call(
                    TablePrivilegeTypeEnum.SELECT, table_name, "principal2", catalog
                ),
                unittest.mock.call(
                    TablePrivilegeTypeEnum.APPLY_TAG, table_name, "principal2", catalog
                ),
            ]
        )

    def test_from_input_dict(self):
        # arrange
        input_dict = {
            "principal": ["SELECT"],
            "principal2": ["SELECT", "APPLY TAG", "MODIFY"],
            "principal3": ["ALL PRIVILEGES"],
        }
        table_name = "table_name"
        catalog = "catalog"

        # act
        table_privileges = TablePrivileges.from_input_dict(
            input_dict, table_name, catalog
        )

        # assert
        self.assertEqual(table_privileges.table_name, table_name)
        self.assertEqual(table_privileges.catalog, catalog)
        self.assertEqual(
            table_privileges.permissions_by_principal,
            {
                "principal": [TablePrivilegeTypeEnum.SELECT],
                "principal2": [
                    TablePrivilegeTypeEnum.SELECT,
                    TablePrivilegeTypeEnum.APPLY_TAG,
                    TablePrivilegeTypeEnum.MODIFY,
                ],
                "principal3": [TablePrivilegeTypeEnum.ALL_PRIVILEGES],
            },
        )

    def test_from_input_dict_invalid_permission(self):
        # arrange
        input_dict = {"principal": ["INVALID_PERMISSION"]}
        table_name = "table_name"
        catalog = "catalog"

        # act and assert
        with self.assertRaises(ValueError):
            TablePrivileges.from_input_dict(input_dict, table_name, catalog)

    @patch.dict(os.environ, {"ENVIRONMENT": "forno"})
    def test_from_environment_default(self):
        # arrange
        table_name = "table_name"
        catalog = "catalog"

        # act
        table_privileges = TablePrivileges.from_environment_default(table_name, catalog)

        # assert
        self.assertEqual(table_privileges.table_name, table_name)
        self.assertEqual(table_privileges.catalog, catalog)
        self.assertEqual(
            table_privileges.permissions_by_principal,
            {
                f"forno-read-only": [TablePrivilegeTypeEnum.SELECT],
                f"forno-read-write": [
                    TablePrivilegeTypeEnum.SELECT,
                    TablePrivilegeTypeEnum.MODIFY,
                    TablePrivilegeTypeEnum.APPLY_TAG,
                ],
            },
        )
