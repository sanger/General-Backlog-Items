-- DELIMITER $$
-- CREATE DEFINER=`mlwh_admin`@`%` PROCEDURE `billing_report_stored_proc`(IN from_date DATETIME, IN to_date DATETIME)
-- BEGIN
--     DECLARE control_phix VARCHAR(30);
--     DECLARE control_illumina VARCHAR(30);
--     SET control_phix = 'Heron PhiX';
--     SET control_illumina = 'Illumina Controls';

  -- Outer query
  -- This grouping calculates the `total` amount of lanes occupied by samples in a given "group" (see end of query)
  SELECT
    iseq_run_lane_metrics.instrument_model     AS platform
    , iseq_flowcell.cost_code                  AS project_cost_code
	 , study.id_study_lims                      AS study_id
    , iseq_run_lane_metrics.position           AS lane_position
    , iseq_flowcell.id_flowcell_lims           AS batch_id
    , study.name                               AS study_name
    , IF(iseq_run_lane_metrics.instrument_model = 'MiSeq', SUBSTRING_INDEX(SUBSTRING_INDEX(iseq_run_lane_metrics.flowcell_barcode, '-', 2), '-', -1), null)
                                               AS reagent_kit_barcode
    , IF(iseq_run_lane_metrics.instrument_model = 'NovaSeq', ExtractValue(iseq_run_info.run_parameters_xml, '//SbsCycleKit'), null)
                                               AS sbs_cycle_kit
    , IF(iseq_run_lane_metrics.qc_seq = 1, 'passed', IF(iseq_run_lane_metrics.qc_seq = '0', 'failed', iseq_run_lane_metrics.qc_seq ))
                                               AS qc_outcome
    , IF(iseq_run.rp__sbs_consumable_version = '1', 'v1', IF(iseq_run.rp__sbs_consumable_version = '3', 'v1.5', iseq_run.rp__sbs_consumable_version))
                                               AS 'v1/1.5'
    , IF(iseq_run.rp__workflow_type = 'NovaSeqXp', 'XP', IF(iseq_run.rp__workflow_type = 'NovaSeqStandard', 'No XP', iseq_run.rp__workflow_type) )
                                               AS xp
    , iseq_run.rp__flow_cell_mode              AS sp
    , iseq_run.rp__read1_number_of_cycles      AS read1
    , iseq_run.rp__read2_number_of_cycles      AS read2
    , SUM(lanes.proportion_of_lane_per_sample) AS total
	 , iseq_flowcell.pipeline_id_lims           AS library
    , COUNT(distinct iseq_flowcell.id_sample_tmp) 			  AS num_samples
    , AVG(iseq_product_metrics.q20_yield_kb_forward_read+iseq_product_metrics.q20_yield_kb_reverse_read) AS q20yield
  FROM
    iseq_run
    INNER JOIN
      (
        -- Inner query 1
        -- There can be multiple QC complete run events,
        -- this query finds all "QC complete" runs within a given timeframe.
        -- Group by run ID.
        -- If there are more than 1 "QC complete" events for a given run ID,
        -- select only the first completed run (based on min `date`)
        SELECT
          id_run
          , MIN(date) AS qc_complete_date
        FROM
          iseq_run_status
          INNER JOIN
            iseq_run_status_dict
            ON iseq_run_status_dict.id_run_status_dict = iseq_run_status.id_run_status_dict
        WHERE
          iseq_run_status_dict.description = 'qc complete'
          AND date(iseq_run_status.date) >= '2022-07-24 00:00:00' -- date() wrapper required throughout for Tableau
          AND date(iseq_run_status.date) <= '2022-07-25 23:59:59'
        GROUP BY
          iseq_run_status.id_run
      )
      AS qc_complete
      ON qc_complete.id_run = iseq_run.id_run
    -- not all runs have run info
    LEFT OUTER JOIN
      iseq_run_info
      ON iseq_run.id_run = iseq_run_info.id_run
    INNER JOIN
      iseq_product_metrics
      ON iseq_run.id_run = iseq_product_metrics.id_run
    INNER JOIN
      iseq_flowcell
      ON iseq_product_metrics.id_iseq_flowcell_tmp = iseq_flowcell.id_iseq_flowcell_tmp
    INNER JOIN
      study
      ON iseq_flowcell.id_study_tmp = study.id_study_tmp
    INNER JOIN
      iseq_run_lane_metrics
      ON iseq_product_metrics.id_run = iseq_run_lane_metrics.id_run
      AND iseq_product_metrics.position = iseq_run_lane_metrics.position
    INNER JOIN
      (
        -- Inner query 2
        -- Group samples by lane ID
        -- Count the number of samples (exluding controls) in a lane
        -- Assuming equal distribution, calculate the proportion of lane occupied per sample (1/ number of samples)
        -- Append this information to the sample, joining on lane ID
        SELECT
          samples.*
          , format(1 / COUNT(*), 10) AS proportion_of_lane_per_sample
        FROM
          (
            -- Inner query 3
            -- Get the samples for the specific runs
            -- Excluding controls
            SELECT
              iseq_flowcell.entity_id_lims AS lane_id
              , iseq_flowcell.cost_code AS project_cost_code
              , study.name
            FROM
              iseq_run
              INNER JOIN
                (
                  -- Inner query 4
                  -- This is the same as Inner query 1 (see above)
                  SELECT
                    id_run
                    , MIN(date) AS qc_complete_date
                  FROM
                    iseq_run_status
                    INNER JOIN
                      iseq_run_status_dict
                      ON iseq_run_status_dict.id_run_status_dict = iseq_run_status.id_run_status_dict
                  WHERE
                    iseq_run_status_dict.description = 'qc complete'
                    AND date(iseq_run_status.date) >= '2022-07-24 00:00:00'
                    AND date(iseq_run_status.date) <= '2022-07-25 23:59:59'
                  GROUP BY
                    iseq_run_status.id_run
                )
                AS qc_complete
                ON qc_complete.id_run = iseq_run.id_run
              INNER JOIN
                iseq_product_metrics
                ON iseq_run.id_run = iseq_product_metrics.id_run
              INNER JOIN
                iseq_run_lane_metrics
                ON iseq_product_metrics.id_run = iseq_run_lane_metrics.id_run
                AND iseq_product_metrics.position = iseq_run_lane_metrics.position
              INNER JOIN
                iseq_flowcell
                ON iseq_product_metrics.id_iseq_flowcell_tmp = iseq_flowcell.id_iseq_flowcell_tmp
              INNER JOIN
                study
                ON iseq_flowcell.id_study_tmp = study.id_study_tmp
            WHERE
                -- Controls are excluded, see Confluence documentation
              study.name NOT IN ('Heron PhiX', 'Illumina Controls')
          )
          AS samples
        GROUP BY
          samples.lane_id
      )
      AS lanes
      ON lanes.lane_id = iseq_flowcell.entity_id_lims
  WHERE
    -- Controls are excluded, see Confluence documentation
    study.name NOT IN ('Heron PhiX', 'Illumina Controls')
  GROUP BY
    study.id_study_lims
    , project_cost_code
    , platform
    , qc_outcome
    , iseq_run.rp__workflow_type
    , iseq_run.rp__flow_cell_mode
	 , iseq_flowcell.id_flowcell_lims -- batch_id
    , iseq_run_lane_metrics.position -- lane_position
  ORDER BY study_name
  ;
-- END$$
-- DELIMITER ;
