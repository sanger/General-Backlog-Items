-- This query is a refactored version of the original billing report query.
-- It uses Common Table Expressions (CTEs) for better readability and maintainability.
-- It includes Stock Plate information
-- and groups by Study Name, Project Cost Code, and Stock Plate Barcode.

-- DELIMITER $$
-- CREATE DEFINER=`mlwh_admin`@`%` PROCEDURE `billing_report_stored_proc`(
--     IN from_date DATETIME,
--     IN to_date   DATETIME
-- )
-- BEGIN
--     DECLARE control_phix VARCHAR(30) DEFAULT 'Heron PhiX';
--     DECLARE control_illumina VARCHAR(30) DEFAULT 'Illumina Controls';

    WITH
    -- CTE 1: qc_complete
    -- Find the first QC-complete event for each run
    qc_complete AS (
        SELECT
            rs.id_run,
            MIN(rs.date) AS qc_complete_date
        FROM iseq_run_status rs
        JOIN iseq_run_status_dict d
              ON d.id_run_status_dict = rs.id_run_status_dict
        WHERE d.description = 'qc complete'
          AND DATE(rs.date) >= DATE('2022-07-24 00:00:00')
          AND DATE(rs.date) <= DATE('2022-07-25 23:59:59')
        GROUP BY rs.id_run
    ),
    -- CTE 2: sample_lanes
    -- Collect all samples on a lane (excluding controls)
    sample_lanes AS (
        SELECT
            r.id_run
            , fc.entity_id_lims AS lane_id
            , fc.cost_code      AS project_cost_code
            , st.name           AS study_name
            , st.id_study_lims  AS study_id
            , lm.position       AS lane_position
            , sr.labware_human_barcode AS stock_plate_barcode -- stock plate if it exists
            , s.id_sample_tmp
            , fc.id_flowcell_lims AS batch_id
            , lm.instrument_model AS platform
            , IF(lm.instrument_model = 'MiSeq', SUBSTRING_INDEX(SUBSTRING_INDEX(lm.flowcell_barcode, '-', 2), '-', -1), null)
                                               AS reagent_kit_barcode
            , IF(lm.instrument_model = 'NovaSeq', ExtractValue(ri.run_parameters_xml, '//SbsCycleKit'), null)
                                               AS sbs_cycle_kit
            , IF(lm.qc_seq = 1, 'passed', IF(lm.qc_seq = '0', 'failed', lm.qc_seq ))
                                               AS qc_outcome
            , IF(r.rp__sbs_consumable_version = '1', 'v1', IF(r.rp__sbs_consumable_version = '3', 'v1.5', r.rp__sbs_consumable_version))
                                               AS 'v1/1.5'
            , IF(r.rp__workflow_type = 'NovaSeqXp', 'XP', IF(r.rp__workflow_type = 'NovaSeqStandard', 'No XP', r.rp__workflow_type) )
                                               AS xp
            , r.rp__flow_cell_mode              AS sp
            , r.rp__read1_number_of_cycles      AS read1
            , r.rp__read2_number_of_cycles      AS read2
            , fc.pipeline_id_lims               AS library
            , pm.q20_yield_kb_forward_read + pm.q20_yield_kb_reverse_read AS q20_yield
        FROM iseq_run r
        LEFT JOIN iseq_run_info ri ON ri.id_run = r.id_run  -- not all runs have run_info
        JOIN qc_complete qc ON qc.id_run = r.id_run
        JOIN iseq_product_metrics pm ON pm.id_run = r.id_run
        JOIN iseq_run_lane_metrics lm
            ON lm.id_run = pm.id_run
           AND lm.position = pm.position
        JOIN iseq_flowcell fc
            ON pm.id_iseq_flowcell_tmp = fc.id_iseq_flowcell_tmp
        LEFT JOIN sample s
            ON s.id_sample_tmp = fc.id_sample_tmp
        LEFT JOIN stock_resource sr
            ON sr.id_sample_tmp = s.id_sample_tmp
        JOIN study st
            ON fc.id_study_tmp = st.id_study_tmp
        -- don't include controls in the overall sample_lane set
        WHERE st.name NOT IN ('Heron PhiX', 'Illumina Controls')
    ),
    -- CTE 3: lane_proportions
    -- For each lane: count samples & compute 1/N
    lane_proportions AS (
        SELECT
            lane_id
            , FORMAT(1 / COUNT(*), 10) AS proportion_of_lane_per_sample
        FROM sample_lanes
        GROUP BY lane_id
    )
    -- Main Final query
    SELECT
        sample_lanes.platform   -- grouped
        , sample_lanes.project_cost_code -- grouped
        , sample_lanes.study_id -- grouped
        , sample_lanes.lane_position -- grouped
        , sample_lanes.batch_id -- grouped
        , GROUP_CONCAT(DISTINCT sample_lanes.study_name SEPARATOR ';') AS study_name -- effectively grouped
--        , sample_lanes.stock_plate_barcode. -- grouped
        , GROUP_CONCAT(DISTINCT sample_lanes.reagent_kit_barcode SEPARATOR ';') AS reagent_kit_barcode -- effectively 1 to 1 with platform
        , GROUP_CONCAT(DISTINCT sample_lanes.sbs_cycle_kit SEPARATOR ';')  AS sbs_cycle_kit -- effectively 1 to 1 with platform
        , sample_lanes.qc_outcome -- grouped
        , GROUP_CONCAT(DISTINCT sample_lanes.`v1/1.5` SEPARATOR ';') AS `v1/1.5`
        , sample_lanes.xp -- grouped
        , sample_lanes.sp -- grouped
        , GROUP_CONCAT(DISTINCT sample_lanes.read1 SEPARATOR ';') AS read1
        , GROUP_CONCAT(DISTINCT sample_lanes.read2 SEPARATOR ';') AS read2
        , SUM(lane_proportions.proportion_of_lane_per_sample) AS total
        , sample_lanes.library -- grouped
        , COUNT(DISTINCT sample_lanes.id_sample_tmp) AS num_samples
        , AVG(sample_lanes.q20_yield) AS q20yield
    FROM iseq_run
    JOIN sample_lanes ON sample_lanes.id_run = iseq_run.id_run
    JOIN lane_proportions ON lane_proportions.lane_id = sample_lanes.lane_id
   
    GROUP BY
        sample_lanes.study_id
        , project_cost_code
        , platform
        , qc_outcome
        , sample_lanes.xp
        , sample_lanes.sp
        , sample_lanes.batch_id
        , sample_lanes.library
        , sample_lanes.lane_position
--        stock_plate_barcode
    ORDER BY sample_lanes.study_name
        , project_cost_code
        , platform
        , qc_outcome
        , sample_lanes.xp
        , sample_lanes.sp
        , sample_lanes.batch_id
        , sample_lanes.library
        , sample_lanes.lane_position
--        stock_plate_barcode
    ;

-- END$$
-- DELIMITER ;

