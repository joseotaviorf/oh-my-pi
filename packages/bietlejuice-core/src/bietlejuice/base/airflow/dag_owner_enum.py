import re


class DAGOwnerEnum:
    """
    Mapping of all Analytics and Data Engineering teams for defining DAG owners.
    DISCLAIMER: Values MUST NOT contain special characters
    """

    DEFAULT_OWNER = "Data Engineering"
    DATA_AGENTS = "Data Agents"
    DATA_ATLAS_DB = "Data Atlas DB"
    DATA_BROKER_XP = "Data Broker XP"
    DATA_CONVERSATIONAL_XP = "Data Conversational XP"
    DATA_PUBLISHER_XP = "Data Publisher XP"
    DATA_DS_PRICING = "Data DS Pricing"
    DATA_FINTECH = "Data Fintech"
    DATA_FOR_RENT = "Data ForRent"
    DATA_FOR_SALE = "Data ForSale"
    DATA_JOURNEY_OPTIMIZER = "Data Journey Optimizer"
    DATA_HOUSE_AND_LISTING = "Data House and Listing"
    DATA_GOVERNANCE = "Data Governance"
    DATA_GROWTH = "Data Growth"
    DATA_PEOPLE = "Data People"
    DATA_PLATFORM = "Data Platform"
    DATA_LIFE_CYCLE = "Data Life Cycle"
    DATA_SS = "Data SS"
    DATA_PP = "Data Planning and Performance"
    MLOPS = "MLOps"
    OPS_FINANCE = "Ops Finance"
    OPS_POC = "Ops POC"
    QCX = "QCX"
    TECH_PLATAFORM_CYBER_SECURITY = "Tech Platform Cyber Security"
    TECH_PLATAFORM_DEV_FOUNDATION = "Tech Platform Dev Foundation"
    TECH_PLATAFORM_ENGINEERING_PRODUCTIVITY = "Tech Platform Engineering Productivity"
    TECH_PLATAFORM_WORKFORCE_PRODUCTIVITY = "Tech Platform Workforce Productivity"

    @classmethod
    def get_available_enum_values(cls):
        values = [
            v
            for k, v in cls.__dict__.items()
            if not k.startswith("_") and isinstance(v, str)
        ]
        invalid_values = [v for v in values if not re.match(r"^[A-Za-z0-9 ]+$", v)]
        if invalid_values:
            raise ValueError(
                f"DAGOwnerEnum contains invalid values with special characters: {invalid_values}"
            )
        return values
