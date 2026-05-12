from enum import Enum


class TablePrivilegeTypeEnum(Enum):
    ALL_PRIVILEGES = "ALL PRIVILEGES"
    APPLY_TAG = "APPLY TAG"
    MODIFY = "MODIFY"
    SELECT = "SELECT"

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]
