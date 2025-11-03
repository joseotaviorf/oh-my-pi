import pytest
from datetime import date
from unittest.mock import Mock, MagicMock
from pyspark.sql.types import StructType, StructField, StringType, ArrayType, IntegerType, BooleanType, TimestampType


@pytest.fixture
def mock_spark_client():
    """Mock SparkClient with a mocked Spark session"""
    client = Mock()
    client.conn = Mock()
    client.conn.sql = Mock()
    return client


@pytest.fixture
def sample_base_relationships_data():
    """Sample base manager-employee relationships from The Office hierarchy.
    
    Hierarchy: David Wallace (CFO) -> Michael Scott (Regional Manager) 
               -> Jim Halpert (Co-Manager) -> Dwight Schrute (Assistant Regional Manager)
    """
    return [
        {
            "assignment_number": "100001",
            "employee_name": "Dwight Schrute",
            "manager_assignment_number": "100002",
            "manager_name": "Jim Halpert",
            "dt_effective_started": date(2023, 1, 1),
            "dt_effective_ended": date(4712, 12, 31)
        },
        {
            "assignment_number": "100002",
            "employee_name": "Jim Halpert",
            "manager_assignment_number": "100003",
            "manager_name": "Michael Scott",
            "dt_effective_started": date(2023, 1, 1),
            "dt_effective_ended": date(4712, 12, 31)
        },
        {
            "assignment_number": "100003",
            "employee_name": "Michael Scott",
            "manager_assignment_number": "100004",
            "manager_name": "David Wallace",
            "dt_effective_started": date(2023, 1, 1),
            "dt_effective_ended": date(4712, 12, 31)
        }
    ]


@pytest.fixture
def sample_level_1_data():
    """Sample level 1 hierarchy data with direct manager relationships only."""
    return [
        {
            "assignment_number": "100001",
            "employee_name": "Dwight Schrute",
            "manager_assignment_number_chain": ["100002"],
            "manager_name_chain": ["Jim Halpert"],
            "dt_started": date(2023, 1, 1),
            "dt_ended": date(4712, 12, 31)
        },
        {
            "assignment_number": "100002",
            "employee_name": "Jim Halpert",
            "manager_assignment_number_chain": ["100003"],
            "manager_name_chain": ["Michael Scott"],
            "dt_started": date(2023, 1, 1),
            "dt_ended": date(4712, 12, 31)
        }
    ]


@pytest.fixture
def sample_pivoted_data():
    """Sample data after pivoting hierarchy to columns.
    
    Columns are ordered from CEO (l0) to direct manager (highest lX).
    David Wallace (l0) -> Michael Scott (l1) -> Jim Halpert (l2) -> Dwight Schrute (employee)
    """
    return [
        {
            "assignment_number": "100001",
            "employee_name": "Dwight Schrute",
            "name_l0": "David Wallace",
            "assignment_number_l0": "100004",
            "name_l1": "Michael Scott",
            "assignment_number_l1": "100003",
            "name_l2": "Jim Halpert",
            "assignment_number_l2": "100002",
            "name_l3": None,
            "assignment_number_l3": None,
            "dt_started": date(2023, 1, 1),
            "dt_ended": date(4712, 12, 31)
        }
    ]


@pytest.fixture
def base_relationships_schema():
    """Schema for base relationships DataFrame"""
    return StructType([
        StructField("assignment_number", StringType(), True),
        StructField("employee_name", StringType(), True),
        StructField("manager_assignment_number", StringType(), True),
        StructField("manager_name", StringType(), True),
        StructField("dt_effective_started", StringType(), True),
        StructField("dt_effective_ended", StringType(), True),
    ])


@pytest.fixture
def hierarchy_chain_schema():
    """Schema for hierarchy with chains"""
    return StructType([
        StructField("assignment_number", StringType(), True),
        StructField("employee_name", StringType(), True),
        StructField("manager_assignment_number_chain", ArrayType(StringType()), True),
        StructField("manager_name_chain", ArrayType(StringType()), True),
        StructField("dt_started", StringType(), True),
        StructField("dt_ended", StringType(), True),
    ])


@pytest.fixture
def mock_dataframe():
    """Mock PySpark DataFrame"""
    df = MagicMock()
    df.count.return_value = 10
    df.select.return_value = df
    df.filter.return_value = df
    df.withColumn.return_value = df
    df.alias.return_value = df
    df.join.return_value = df
    df.union.return_value = df
    df.groupBy.return_value = df
    df.agg.return_value = df
    df.drop.return_value = df
    df.orderBy.return_value = df
    return df


@pytest.fixture
def mock_datalake_metastore_service():
    """Mock DatalakeMetastoreService"""
    with pytest.mock.patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.DatalakeMetastoreService') as mock:
        mock.get_db_info.return_value = {
            "db_enrich_databricks": "test_database",
            "db_enrich_path": "s3://test-bucket/test-path/"
        }
        yield mock


@pytest.fixture
def mock_spark_metastore_service():
    """Mock SparkMetastoreService"""
    service = Mock()
    service.create_database = Mock()
    service.refresh_table = Mock()
    return service


@pytest.fixture
def mock_delta_loader():
    """Mock DeltaLoader"""
    loader = Mock()
    loader.load_table = Mock()
    return loader

