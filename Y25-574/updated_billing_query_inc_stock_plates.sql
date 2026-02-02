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
            r.id_run,
            fc.entity_id_lims AS lane_id,
            fc.cost_code      AS project_cost_code,
            st.name           AS study_name,
            st.id_study_lims  AS study_id,
            sr.labware_human_barcode AS stock_plate_barcode, -- stock plate if it exists
            s.id_sample_tmp,
            fc.id_flowcell_lims AS batch_id,
            lm.instrument_model     AS platform

        FROM iseq_run r
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
    ),
    -- CTE 3: lane_proportions
    -- For each lane: count samples & compute 1/N
    lane_proportions AS (
        SELECT
            lane_id,
            FORMAT(1 / COUNT(*), 10) AS proportion_of_lane_per_sample
        FROM sample_lanes
        GROUP BY lane_id
    )
    -- Main Final query
    SELECT
        sample_lanes.platform,
        sample_lanes.project_cost_code,
        sample_lanes.study_id,
        sample_lanes.study_name,
        sample_lanes.stock_plate_barcode,
        SUM(lane_proportions.proportion_of_lane_per_sample) AS total
    FROM iseq_run
    JOIN sample_lanes ON sample_lanes.id_run = iseq_run.id_run
    JOIN lane_proportions ON lane_proportions.lane_id = sample_lanes.lane_id
    WHERE sample_lanes.study_name NOT IN ('Heron PhiX', 'Illumina Controls')

    GROUP BY
        sample_lanes.study_name,
        project_cost_code,
        stock_plate_barcode
    ORDER BY sample_lanes.study_name
    ;

-- END$$
-- DELIMITER ;
