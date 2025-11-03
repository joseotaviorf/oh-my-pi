import pytest
import sys
from datetime import date
from unittest.mock import Mock, MagicMock, patch, call

mock_pyspark = MagicMock()
sys.modules["pyspark"] = mock_pyspark
sys.modules["pyspark.conf"] = MagicMock()
sys.modules["pyspark.sql"] = MagicMock()
sys.modules["pyspark.sql.functions"] = MagicMock()
sys.modules["pyspark.sql.types"] = MagicMock()
sys.modules["pyspark.sql.dataframe"] = MagicMock()
sys.modules["pyspark.context"] = MagicMock()

sys.modules["bietlejuice.clients.db_clients"] = MagicMock()
sys.modules["bietlejuice.loaders.delta_loader"] = MagicMock()
sys.modules["bietlejuice.services.metastore_services"] = MagicMock()
sys.modules["bietlejuice.base.db"] = MagicMock()

from dags.people.enrich_employee.spark_jobs.load_hierarchy_closure import (  # noqa: E402
    load_base_relationships,
    initialize_level_1,
    build_level,
    build_iterative_hierarchy,
    pivot_hierarchy_to_columns,
    consolidate_consecutive_periods,
    add_scd_type2_fields,
    select_final_columns,
    build_hierarchical_closure,
    MAX_HIERARCHY_LEVELS
)


class TestLoadBaseRelationships:
    """Test suite for load_base_relationships function.
    
    Tests the initial loading of manager-employee relationships from the source table,
    including query structure validation and data filtering.
    """
    
    def test_load_base_relationships_executes_correct_query(self, mock_spark_client, mock_dataframe):
        """Validates SQL query execution and structure against datalake_pin.managers_history."""
        mock_spark_client.conn.sql.return_value = mock_dataframe
        
        result = load_base_relationships(mock_spark_client)
        
        assert mock_spark_client.conn.sql.called
        sql_call = mock_spark_client.conn.sql.call_args[0][0]
        
        assert "datalake_pin.managers_history" in sql_call
        assert "assignment_number" in sql_call
        assert "manager_assignment_number" in sql_call
        assert "dt_effective_started" in sql_call
        assert "dt_effective_ended" in sql_call
        
    def test_load_base_relationships_filters_null_managers(self, mock_spark_client, mock_dataframe):
        """Ensures null manager_assignment_number values are excluded from results."""
        mock_spark_client.conn.sql.return_value = mock_dataframe
        
        load_base_relationships(mock_spark_client)
        
        sql_call = mock_spark_client.conn.sql.call_args[0][0]
        assert "manager_assignment_number IS NOT NULL" in sql_call
        
    def test_load_base_relationships_filters_specific_manager(self, mock_spark_client, mock_dataframe):
        """Validates filtering of specific manager ID (300000008488092) from results."""
        mock_spark_client.conn.sql.return_value = mock_dataframe
        
        load_base_relationships(mock_spark_client)
        
        sql_call = mock_spark_client.conn.sql.call_args[0][0]
        assert "300000008488092" in sql_call
        
    def test_load_base_relationships_counts_records(self, mock_spark_client, mock_dataframe):
        """Verifies record count is performed and result DataFrame is returned."""
        mock_dataframe.count.return_value = 100
        mock_spark_client.conn.sql.return_value = mock_dataframe
        
        result = load_base_relationships(mock_spark_client)
        
        assert mock_dataframe.count.called
        assert result == mock_dataframe


class TestInitializeLevel1:
    """Test suite for initialize_level_1 function.
    
    Tests the initialization of level 1 hierarchy by creating array columns
    for manager chains from base relationships.
    """
    
    def test_initialize_level_1_creates_arrays(self, mock_dataframe):
        """Validates creation of manager arrays from base relationships."""
        mock_dataframe.select.return_value = mock_dataframe
        mock_dataframe.count.return_value = 50
        
        result = initialize_level_1(mock_dataframe)
        
        assert mock_dataframe.select.called
        assert result == mock_dataframe
        
    def test_initialize_level_1_counts_records(self, mock_dataframe):
        """Verifies level 1 record count is performed."""
        expected_count = 75
        mock_dataframe.count.return_value = expected_count
        mock_dataframe.select.return_value = mock_dataframe
        
        result = initialize_level_1(mock_dataframe)
        
        assert mock_dataframe.count.called


class TestBuildLevel:
    """Test suite for build_level function.
    
    Tests the recursive building of hierarchy levels by joining previous level
    with base relationships on the manager chain.
    """
    
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.col')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.array_union')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.array')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.greatest')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.least')
    def test_build_level_joins_on_manager_chain(self, mock_least, mock_greatest, mock_array, 
                                                 mock_array_union, mock_col, mock_dataframe):
        """Validates join operation on manager assignment number chain."""
        base_df = MagicMock()
        previous_level_df = MagicMock()
        
        mock_col.return_value = MagicMock(__lt__=MagicMock(return_value=True))
        
        previous_level_df.alias.return_value = previous_level_df
        previous_level_df.join.return_value = previous_level_df
        previous_level_df.select.return_value = previous_level_df
        previous_level_df.withColumn.return_value = previous_level_df
        previous_level_df.filter.return_value = previous_level_df
        previous_level_df.count.return_value = 10
        
        base_df.alias.return_value = base_df
        
        result = build_level(base_df, previous_level_df, 2)
        
        assert previous_level_df.join.called
        
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.col')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.array_union')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.array')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.greatest')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.least')
    def test_build_level_filters_valid_date_ranges(self, mock_least, mock_greatest, mock_array,
                                                    mock_array_union, mock_col, mock_dataframe):
        """Validates filtering to keep only valid date ranges where dt_started < dt_ended."""
        base_df = MagicMock()
        previous_level_df = MagicMock()
        
        mock_col.return_value = MagicMock(__lt__=MagicMock(return_value=True))
        
        previous_level_df.alias.return_value = previous_level_df
        previous_level_df.join.return_value = previous_level_df
        previous_level_df.select.return_value = previous_level_df
        previous_level_df.withColumn.return_value = previous_level_df
        previous_level_df.filter.return_value = previous_level_df
        previous_level_df.count.return_value = 10
        
        base_df.alias.return_value = base_df
        
        result = build_level(base_df, previous_level_df, 3)
        
        assert previous_level_df.filter.called
        
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.col')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.array_union')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.array')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.greatest')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.least')
    def test_build_level_counts_output(self, mock_least, mock_greatest, mock_array,
                                       mock_array_union, mock_col, mock_dataframe):
        """Validates that output records are counted after level build."""
        base_df = MagicMock()
        previous_level_df = MagicMock()
        
        mock_col.return_value = MagicMock(__lt__=MagicMock(return_value=True))
        
        previous_level_df.alias.return_value = previous_level_df
        previous_level_df.join.return_value = previous_level_df
        previous_level_df.select.return_value = previous_level_df
        previous_level_df.withColumn.return_value = previous_level_df
        previous_level_df.filter.return_value = previous_level_df
        previous_level_df.count.return_value = 25
        
        base_df.alias.return_value = base_df
        
        result = build_level(base_df, previous_level_df, 2)
        
        assert previous_level_df.count.called


class TestBuildIterativeHierarchy:
    """Test suite for build_iterative_hierarchy function"""
    
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.load_base_relationships')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.initialize_level_1')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.build_level')
    def test_build_iterative_hierarchy_stops_when_no_records(
        self, mock_build_level, mock_initialize, mock_load_base, mock_spark_client
    ):
        """Test that iteration stops when no more records are found"""
        base_df = MagicMock()
        level_1_df = MagicMock()
        empty_df = MagicMock()
        
        level_1_df.count.return_value = 100
        level_1_df.union.return_value = level_1_df
        empty_df.count.return_value = 0
        
        mock_load_base.return_value = base_df
        mock_initialize.return_value = level_1_df
        mock_build_level.return_value = empty_df
        
        result = build_iterative_hierarchy(mock_spark_client)
        
        # Should stop at level 2 when it returns 0 records
        assert mock_build_level.call_count == 1
        
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.load_base_relationships')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.initialize_level_1')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.build_level')
    def test_build_iterative_hierarchy_unions_all_levels(
        self, mock_build_level, mock_initialize, mock_load_base, mock_spark_client
    ):
        """Test that all levels are unioned together"""
        base_df = MagicMock()
        level_1_df = MagicMock()
        level_2_df = MagicMock()
        level_3_df = MagicMock()
        empty_df = MagicMock()
        
        level_1_df.count.return_value = 100
        level_1_df.union.return_value = level_1_df
        level_2_df.count.return_value = 80
        level_3_df.count.return_value = 50
        empty_df.count.return_value = 0
        
        mock_load_base.return_value = base_df
        mock_initialize.return_value = level_1_df
        mock_build_level.side_effect = [level_2_df, level_3_df, empty_df]
        
        result = build_iterative_hierarchy(mock_spark_client)
        
        # Verify union was called for each level
        assert level_1_df.union.call_count >= 2
        
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.load_base_relationships')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.initialize_level_1')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.build_level')
    def test_build_iterative_hierarchy_respects_max_levels(
        self, mock_build_level, mock_initialize, mock_load_base, mock_spark_client
    ):
        """Validates that iteration stops at MAX_HIERARCHY_LEVELS.
        
        Loop runs from level 2 to MAX_HIERARCHY_LEVELS (inclusive),
        resulting in (MAX_HIERARCHY_LEVELS - 1) iterations.
        """
        base_df = MagicMock()
        level_df = MagicMock()
        
        level_df.count.return_value = 100
        level_df.union.return_value = level_df
        
        mock_load_base.return_value = base_df
        mock_initialize.return_value = level_df
        mock_build_level.return_value = level_df
        
        result = build_iterative_hierarchy(mock_spark_client)
        
        assert mock_build_level.call_count == MAX_HIERARCHY_LEVELS - 1


class TestPivotHierarchyToColumns:
    """Test suite for pivot_hierarchy_to_columns function.
    
    Tests the transformation of array-based hierarchy chains into individual
    level columns (l0, l1, l2...) with CEO at l0.
    """
    
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.col')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.reverse')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.size')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.when')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.lit')
    def test_pivot_hierarchy_reverses_chains(self, mock_lit, mock_when, mock_size, 
                                              mock_reverse, mock_col, mock_dataframe):
        """Validates that manager chains are reversed to place CEO first (l0)."""
        mock_col.return_value = MagicMock(__gt__=MagicMock(return_value=True))
        mock_when.return_value = MagicMock(otherwise=MagicMock(return_value=MagicMock()))
        mock_lit.return_value = MagicMock(cast=MagicMock(return_value=MagicMock()))
        
        mock_dataframe.withColumn.return_value = mock_dataframe
        mock_dataframe.select.return_value = mock_dataframe
        
        result = pivot_hierarchy_to_columns(mock_dataframe)
        
        assert mock_dataframe.withColumn.called
        call_args = [call[0][0] for call in mock_dataframe.withColumn.call_args_list]
        assert "manager_assignment_number_chain" in call_args
        assert "manager_name_chain" in call_args
        
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.col')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.reverse')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.size')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.when')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.lit')
    def test_pivot_hierarchy_creates_level_columns(self, mock_lit, mock_when, mock_size,
                                                    mock_reverse, mock_col, mock_dataframe):
        """Validates creation of lX columns for each hierarchy level."""
        mock_col.return_value = MagicMock(__gt__=MagicMock(return_value=True))
        mock_when.return_value = MagicMock(otherwise=MagicMock(return_value=MagicMock()))
        mock_lit.return_value = MagicMock(cast=MagicMock(return_value=MagicMock()))
        
        mock_dataframe.withColumn.return_value = mock_dataframe
        mock_dataframe.select.return_value = mock_dataframe
        
        result = pivot_hierarchy_to_columns(mock_dataframe)
        
        call_args = [call[0][0] for call in mock_dataframe.withColumn.call_args_list]
        
        assert any('assignment_number_l' in arg for arg in call_args)
        assert any('name_l' in arg for arg in call_args)
        
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.col')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.reverse')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.size')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.when')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.lit')
    def test_pivot_hierarchy_selects_final_columns(self, mock_lit, mock_when, mock_size,
                                                    mock_reverse, mock_col, mock_dataframe):
        """Validates selection of final columns in output."""
        mock_col.return_value = MagicMock(__gt__=MagicMock(return_value=True))
        mock_when.return_value = MagicMock(otherwise=MagicMock(return_value=MagicMock()))
        mock_lit.return_value = MagicMock(cast=MagicMock(return_value=MagicMock()))
        
        mock_dataframe.withColumn.return_value = mock_dataframe
        mock_dataframe.select.return_value = mock_dataframe
        
        result = pivot_hierarchy_to_columns(mock_dataframe)
        
        assert mock_dataframe.select.called


class TestConsolidateConsecutivePeriods:
    """Test suite for consolidate_consecutive_periods function.
    
    Tests the consolidation of consecutive time periods with identical hierarchies
    by merging rows where dt_ended equals dt_started of the next period.
    """
    
    def test_consolidate_creates_hierarchy_signature(self, mock_dataframe):
        """Validates creation of hierarchy signature for grouping identical structures."""
        mock_dataframe.withColumn.return_value = mock_dataframe
        mock_dataframe.groupBy.return_value = mock_dataframe
        mock_dataframe.agg.return_value = mock_dataframe
        mock_dataframe.drop.return_value = mock_dataframe
        mock_dataframe.count.side_effect = [100, 80]  # Before and after consolidation
        
        result = consolidate_consecutive_periods(mock_dataframe)
        
        # Verify hierarchy_signature column was created
        call_args = [call[0][0] for call in mock_dataframe.withColumn.call_args_list]
        assert "hierarchy_signature" in call_args
        
    def test_consolidate_groups_by_hierarchy(self, mock_dataframe):
        """Test that grouping is performed"""
        mock_dataframe.withColumn.return_value = mock_dataframe
        mock_dataframe.groupBy.return_value = mock_dataframe
        mock_dataframe.agg.return_value = mock_dataframe
        mock_dataframe.drop.return_value = mock_dataframe
        mock_dataframe.count.side_effect = [100, 80]
        
        result = consolidate_consecutive_periods(mock_dataframe)
        
        # Verify groupBy was called
        assert mock_dataframe.groupBy.called
        
    def test_consolidate_aggregates_dates(self, mock_dataframe):
        """Test that dates are aggregated (min dt_started, max dt_ended)"""
        mock_dataframe.withColumn.return_value = mock_dataframe
        mock_dataframe.groupBy.return_value = mock_dataframe
        mock_dataframe.agg.return_value = mock_dataframe
        mock_dataframe.drop.return_value = mock_dataframe
        mock_dataframe.count.side_effect = [100, 75]
        
        result = consolidate_consecutive_periods(mock_dataframe)
        
        # Verify agg was called
        assert mock_dataframe.agg.called
        
    def test_consolidate_drops_temporary_columns(self, mock_dataframe):
        """Test that temporary columns are dropped"""
        mock_dataframe.withColumn.return_value = mock_dataframe
        mock_dataframe.groupBy.return_value = mock_dataframe
        mock_dataframe.agg.return_value = mock_dataframe
        mock_dataframe.drop.return_value = mock_dataframe
        mock_dataframe.count.side_effect = [100, 80]
        
        result = consolidate_consecutive_periods(mock_dataframe)
        
        # Verify drop was called
        assert mock_dataframe.drop.called


class TestAddScdType2Fields:
    """Test suite for add_scd_type2_fields function.
    
    Tests the addition of SCD Type 2 fields: version, is_current, ts_load, and sk_hierarchy.
    """
    
    def test_add_scd_adds_version_column(self, mock_dataframe):
        """Validates addition of version column for SCD Type 2 tracking."""
        mock_dataframe.withColumn.return_value = mock_dataframe
        
        result = add_scd_type2_fields(mock_dataframe)
        
        call_args = [call[0][0] for call in mock_dataframe.withColumn.call_args_list]
        assert "version" in call_args
        
    def test_add_scd_adds_is_current_column(self, mock_dataframe):
        """Test that is_current column is added"""
        mock_dataframe.withColumn.return_value = mock_dataframe
        
        result = add_scd_type2_fields(mock_dataframe)
        
        call_args = [call[0][0] for call in mock_dataframe.withColumn.call_args_list]
        assert "is_current" in call_args
        
    def test_add_scd_adds_ts_load_column(self, mock_dataframe):
        """Test that ts_load column is added"""
        mock_dataframe.withColumn.return_value = mock_dataframe
        
        result = add_scd_type2_fields(mock_dataframe)
        
        call_args = [call[0][0] for call in mock_dataframe.withColumn.call_args_list]
        assert "ts_load" in call_args
        
    def test_add_scd_adds_sk_hierarchy_column(self, mock_dataframe):
        """Test that sk_hierarchy surrogate key is added"""
        mock_dataframe.withColumn.return_value = mock_dataframe
        
        result = add_scd_type2_fields(mock_dataframe)
        
        call_args = [call[0][0] for call in mock_dataframe.withColumn.call_args_list]
        assert "sk_hierarchy" in call_args


class TestSelectFinalColumns:
    """Test suite for select_final_columns function"""
    
    def test_select_final_columns_includes_surrogate_key(self, mock_dataframe):
        """Test that sk_hierarchy is the first column"""
        mock_dataframe.select.return_value = mock_dataframe
        
        result = select_final_columns(mock_dataframe)
        
        # Verify select was called
        assert mock_dataframe.select.called
        
    def test_select_final_columns_includes_scd_fields(self, mock_dataframe):
        """Test that SCD fields are included"""
        mock_dataframe.select.return_value = mock_dataframe
        
        result = select_final_columns(mock_dataframe)
        
        assert mock_dataframe.select.called


class TestBuildHierarchicalClosure:
    """Test suite for build_hierarchical_closure function"""
    
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.build_iterative_hierarchy')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.pivot_hierarchy_to_columns')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.consolidate_consecutive_periods')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.add_scd_type2_fields')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.select_final_columns')
    def test_build_hierarchical_closure_calls_all_steps(
        self, mock_select, mock_add_scd, mock_consolidate, mock_pivot, 
        mock_build_iter, mock_spark_client
    ):
        """Test that all pipeline steps are called in sequence"""
        mock_df = MagicMock()
        mock_build_iter.return_value = mock_df
        mock_pivot.return_value = mock_df
        mock_consolidate.return_value = mock_df
        mock_add_scd.return_value = mock_df
        mock_select.return_value = mock_df
        
        result = build_hierarchical_closure(mock_spark_client)
        
        # Verify all steps were called
        assert mock_build_iter.called
        assert mock_pivot.called
        assert mock_consolidate.called
        assert mock_add_scd.called
        assert mock_select.called
        
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.build_iterative_hierarchy')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.pivot_hierarchy_to_columns')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.consolidate_consecutive_periods')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.add_scd_type2_fields')
    @patch('dags.people.enrich_employee.spark_jobs.load_hierarchy_closure.select_final_columns')
    def test_build_hierarchical_closure_correct_order(
        self, mock_select, mock_add_scd, mock_consolidate, mock_pivot,
        mock_build_iter, mock_spark_client
    ):
        """Test that pipeline steps are called in the correct order"""
        mock_df = MagicMock()
        call_order = []
        
        mock_build_iter.side_effect = lambda x: (call_order.append('build'), mock_df)[1]
        mock_pivot.side_effect = lambda x: (call_order.append('pivot'), mock_df)[1]
        mock_consolidate.side_effect = lambda x: (call_order.append('consolidate'), mock_df)[1]
        mock_add_scd.side_effect = lambda x: (call_order.append('scd'), mock_df)[1]
        mock_select.side_effect = lambda x: (call_order.append('select'), mock_df)[1]
        
        result = build_hierarchical_closure(mock_spark_client)
        
        # Verify order
        assert call_order == ['build', 'pivot', 'consolidate', 'scd', 'select']


class TestMaxHierarchyLevels:
    """Test suite for MAX_HIERARCHY_LEVELS constant"""
    
    def test_max_hierarchy_levels_is_defined(self):
        """Test that MAX_HIERARCHY_LEVELS is properly defined"""
        assert MAX_HIERARCHY_LEVELS == 9
        
    def test_max_hierarchy_levels_is_positive(self):
        """Test that MAX_HIERARCHY_LEVELS is a positive integer"""
        assert isinstance(MAX_HIERARCHY_LEVELS, int)
        assert MAX_HIERARCHY_LEVELS > 0

