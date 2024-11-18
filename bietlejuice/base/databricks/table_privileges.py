import os
from typing import List, Dict
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.base.databricks.table_privilege_type_enum import TablePrivilegeTypeEnum


class TablePrivileges:
    def __init__(
        self,
        table_name: str,
        permissions_by_principal: Dict[str, List[TablePrivilegeTypeEnum]],
        catalog: str = None,
    ) -> None:
        self.table_name = table_name
        self.permissions_by_principal = permissions_by_principal
        self.catalog = catalog

    def apply(self) -> None:
        for principal, privileges in self.permissions_by_principal.items():
            for privilege in privileges:
                UnityCatalogHelper.grant_table_permission(
                    privilege, self.table_name, principal, self.catalog
                )

    @staticmethod
    def from_input_dict(
        input_dict: Dict[str, List[str]], table_name: str, catalog: str = None
    ) -> "TablePrivileges":
        permissions_by_principal = {}
        for principal, permissions in input_dict.items():
            permissions_by_principal[principal] = []
            for permission in permissions:
                if permission not in TablePrivilegeTypeEnum.get_available_enum_values():
                    raise ValueError(f"Invalid permission {permission}")
                permissions_by_principal[principal].append(
                    TablePrivilegeTypeEnum(permission)
                )

        return TablePrivileges(table_name, permissions_by_principal, catalog)

    @staticmethod
    def from_environment_default(
        table_name: str, catalog: str = None
    ) -> "TablePrivileges":
        env = os.environ.get("ENVIRONMENT").lower()

        return TablePrivileges(
            table_name,
            {
                f"{env}-read-only": [TablePrivilegeTypeEnum.SELECT],
                f"{env}-read-write": [
                    TablePrivilegeTypeEnum.SELECT,
                    TablePrivilegeTypeEnum.MODIFY,
                    TablePrivilegeTypeEnum.APPLY_TAG,
                ],
            },
            catalog,
        )
