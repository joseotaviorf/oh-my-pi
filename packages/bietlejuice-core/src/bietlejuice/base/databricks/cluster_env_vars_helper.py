class ClusterEnvVarsHelper:
    """Helper class to set Spark environment variables based on Databricks runtime version."""

    SPARK_VERSION_MAP = {
        # These are not the real spark versions
        # This will only be used to determine the inmetro and deequ libraries
        "12.2.x-scala2.12": "3.2",  # This is actually 3.3
        "13.3.x-scala2.12": "3.2",  # And this is actually 3.4
        "14.3.x-scala2.12": "3.5",
        "15.4.x-scala2.12": "3.5",
        "16.4.x-scala2.12": "3.5",
    }

    INMETRO_VERSION_MAP = {
        "3.2": "2.3.0",  # Databricks 12.2 and 13.3 - keep compatibility
        "3.3": "4.10.1",  # Databricks 14.3+ - new version with content parameter support
        "3.4": "4.10.1",
        "3.5": "4.10.1",
    }

    DEEQU_VERSION_MAP = {
        "3.2": "2.0.1",
        "3.3": "2.0.8",
        "3.4": "2.0.8",
        "3.5": "2.0.8",
    }

    @classmethod
    def get_spark_version(cls, databricks_version: str) -> str:
        """Maps Databricks runtime version to Spark version.

        Args:
            databricks_version: The Databricks runtime version (e.g., "14.3.x-scala2.12")

        Returns:
            The corresponding Spark version string

        Raises:
            ValueError: If the Databricks version is not in the mapping
        """
        try:
            return cls.SPARK_VERSION_MAP[databricks_version]
        except KeyError as exc:
            raise ValueError(f"Invalid DBR version: {databricks_version}") from exc

    @classmethod
    def get_inmetro_version(cls, spark_version: str) -> str:
        """Maps Spark version to Inmetro library version.

        Args:
            spark_version: The Spark version (e.g., "3.5")

        Returns:
            The corresponding Inmetro version string

        Raises:
            ValueError: If the Spark version is not in the mapping
        """
        try:
            return cls.INMETRO_VERSION_MAP[spark_version]
        except KeyError as exc:
            raise ValueError(f"Invalid Spark version: {spark_version}") from exc

    @classmethod
    def get_deequ_version(cls, spark_version: str) -> str:
        """Maps Spark version to Deequ library version.

        Args:
            spark_version: The Spark version (e.g., "3.5")

        Returns:
            The corresponding Deequ version string

        Raises:
            ValueError: If the Spark version is not in the mapping
        """
        try:
            return cls.DEEQU_VERSION_MAP[spark_version]
        except KeyError as exc:
            raise ValueError(f"Invalid Spark version: {spark_version}") from exc

    @classmethod
    def input_spark_env_vars(cls, cluster_configuration: dict) -> dict:
        """Sets SPARK_VERSION, INMETRO_VERSION, and DEEQU_JAR_VERSION in spark_env_vars.

        Args:
            cluster_configuration: The cluster configuration dictionary containing
                                   spark_version and spark_env_vars keys

        Returns:
            The updated cluster configuration with spark_env_vars populated
        """
        spark_version = cls.get_spark_version(cluster_configuration["spark_version"])

        cluster_configuration["spark_env_vars"]["SPARK_VERSION"] = spark_version
        cluster_configuration["spark_env_vars"]["INMETRO_VERSION"] = (
            cls.get_inmetro_version(spark_version)
        )
        cluster_configuration["spark_env_vars"]["DEEQU_JAR_VERSION"] = (
            cls.get_deequ_version(spark_version)
        )

        return cluster_configuration
