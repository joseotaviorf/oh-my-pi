from enum import Enum


class ServiceEnum(Enum):
    """
    Mapping of secret keys for the services connections parameters stored in
    the Databricks secrets.
    """

    METADATA_PROPAGATOR = "METADATA_PROPAGATOR_SERVICE"
