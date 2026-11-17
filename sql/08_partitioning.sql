-- =====================================================================
-- Google Maps Navigation Database: Table Partitioning DDL (Phase 5 / CP4)
-- Target RDBMS: PostgreSQL 15+
-- Schema: gmaps
--
-- PURPOSE:
-- Implements declarative RANGE partitioning on large, high-volume
-- time-series tables to handle 20x to 100x scale:
--   1. navigation_sessions (200k rows seed -> 4M large -> 20M+ scale)
--      Partitioned by RANGE (started_at) with monthly partition slices.
--   2. traffic_readings (250k rows seed -> 5M large -> 25M+ scale)
--      Partitioned by RANGE (recorded_at) with monthly partition slices.
--
-- KEY POSTGRESQL PARTITIONING RULES DEMONSTRATED:
-- 1. Primary Key Rule: In PostgreSQL declarative partitioning, any UNIQUE
--    or PRIMARY KEY constraint MUST contain all partition key columns.
--    Hence, PRIMARY KEY (session_id, started_at) and (reading_id, recorded_at).
-- 2. Foreign Key constraints: In PostgreSQL 12+, partitioned tables can have
--    incoming and outgoing foreign keys.
-- 3. Partition Pruning: Demonstrates static planning and run-time pruning
--    via EXPLAIN (ANALYZE, BUFFERS), skipping irrelevant partitions.
-- 4. Safe Default Partitions: Catches boundary anomalies without crashing inserts.
-- 5. Automated Partition Management: PL/pgSQL procedure for zero-downtime provisioning.
-- =====================================================================

SET search_path TO gmaps, public;

-- ---------------------------------------------------------------------
-- 1. Declarative RANGE Partitioning for navigation_sessions
-- ---------------------------------------------------------------------

-- Drop existing partitioned table and child partitions if re-running
DROP TABLE IF EXISTS navigation_sessions_partitioned CASCADE;

CREATE TABLE navigation_sessions_partitioned (
    session_id INTEGER NOT NULL,
    user_id INTEGER,
    origin_place_id INTEGER,
    origin_lat DECIMAL(9, 6) NOT NULL,
    origin_lng DECIMAL(9, 6) NOT NULL,
    dest_place_id INTEGER NOT NULL,
    travel_mode VARCHAR(30) NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    distance_km DECIMAL(8, 2) NOT NULL,
    eta_minutes INTEGER NOT NULL,
    actual_minutes INTEGER,
    rerouted_count INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(30) NOT NULL,

    -- PRIMARY KEY CONSTRAINT:
    -- Mandatory PostgreSQL Rule: Partition key 'started_at' MUST be part of PK
    CONSTRAINT pk_nav_partitioned PRIMARY KEY (session_id, started_at),

    -- Foreign Key references to dimension tables
    CONSTRAINT fk_nav_part_user FOREIGN KEY (user_id) 
        REFERENCES users(user_id) ON DELETE SET NULL,
    CONSTRAINT fk_nav_part_origin_place FOREIGN KEY (origin_place_id) 
        REFERENCES places(place_id) ON DELETE SET NULL,
    CONSTRAINT fk_nav_part_dest_place FOREIGN KEY (dest_place_id) 
        REFERENCES places(place_id) ON DELETE RESTRICT,

    -- Domain CHECK constraints matching production schema
    CONSTRAINT chk_nav_part_origin_lat CHECK (origin_lat BETWEEN -90.0 AND 90.0),
    CONSTRAINT chk_nav_part_origin_lng CHECK (origin_lng BETWEEN -180.0 AND 180.0),
    CONSTRAINT chk_nav_part_travel_mode CHECK (
        travel_mode IN ('DRIVE', 'TRANSIT', 'WALK', 'TWO_WHEELER')
    ),
    CONSTRAINT chk_nav_part_status CHECK (status IN ('COMPLETED', 'CANCELLED', 'IN_PROGRESS')),
    CONSTRAINT chk_nav_part_metrics CHECK (
        distance_km >= 0.0 AND eta_minutes > 0 AND rerouted_count >= 0
    ),
    CONSTRAINT chk_nav_part_actual_minutes CHECK (
        (status = 'COMPLETED' AND actual_minutes IS NOT NULL AND actual_minutes > 0) OR
        (status IN ('CANCELLED', 'IN_PROGRESS') AND (actual_minutes IS NULL OR actual_minutes >= 0))
    )
) PARTITION BY RANGE (started_at);

-- ---------------------------------------------------------------------
-- 2. Create Monthly Partitions for navigation_sessions (2025 to 2027)
-- ---------------------------------------------------------------------

-- Year 2025 Partitions
CREATE TABLE navigation_sessions_y2025m01 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-02-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2025m02 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-02-01 00:00:00+05:30') TO ('2025-03-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2025m03 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-03-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2025m04 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-05-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2025m05 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-05-01 00:00:00+05:30') TO ('2025-06-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2025m06 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-06-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2025m07 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-08-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2025m08 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-08-01 00:00:00+05:30') TO ('2025-09-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2025m09 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-09-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2025m10 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2025-11-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2025m11 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-11-01 00:00:00+05:30') TO ('2025-12-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2025m12 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-12-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');

-- Year 2026 Partitions
CREATE TABLE navigation_sessions_y2026m01 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-02-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2026m02 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-02-01 00:00:00+05:30') TO ('2026-03-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2026m03 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-03-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2026m04 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-05-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2026m05 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-05-01 00:00:00+05:30') TO ('2026-06-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2026m06 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-06-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2026m07 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO ('2026-08-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2026m08 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-08-01 00:00:00+05:30') TO ('2026-09-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2026m09 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-09-01 00:00:00+05:30') TO ('2026-10-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2026m10 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-10-01 00:00:00+05:30') TO ('2026-11-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2026m11 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-11-01 00:00:00+05:30') TO ('2026-12-01 00:00:00+05:30');

CREATE TABLE navigation_sessions_y2026m12 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-12-01 00:00:00+05:30') TO ('2027-01-01 00:00:00+05:30');

-- Default Partition for future-proofing and out-of-band records
CREATE TABLE navigation_sessions_default PARTITION OF navigation_sessions_partitioned DEFAULT;

-- ---------------------------------------------------------------------
-- 3. Partition-Specific Local Indexes
-- PostgreSQL automatically propagates indexes created on the partitioned parent
-- to all child partitions.
-- ---------------------------------------------------------------------

-- Composite index for destination lookups & range filtering (R12, R16, R17, R19)
CREATE INDEX idx_nav_part_dest_started 
    ON navigation_sessions_partitioned (dest_place_id, started_at);

-- User history lookup index
CREATE INDEX idx_nav_part_user_started 
    ON navigation_sessions_partitioned (user_id, started_at DESC) 
    WHERE user_id IS NOT NULL;

-- Origin place index (R13 anti-join optimization)
CREATE INDEX idx_nav_part_origin_place 
    ON navigation_sessions_partitioned (origin_place_id) 
    WHERE origin_place_id IS NOT NULL;

-- Analytics status & travel mode index (R11, R18)
CREATE INDEX idx_nav_part_status_mode 
    ON navigation_sessions_partitioned (status, travel_mode, started_at);

-- ---------------------------------------------------------------------
-- 4. Secondary Example: Partitioning traffic_readings by Month
-- High-frequency telemetry table (250k seed -> 5M large)
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS traffic_readings_partitioned CASCADE;

CREATE TABLE traffic_readings_partitioned (
    reading_id INTEGER NOT NULL,
    segment_id INTEGER NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL,
    avg_speed_kmph DECIMAL(6, 2) NOT NULL,
    congestion_level VARCHAR(30) NOT NULL,

    -- Mandatory PostgreSQL Rule: Partition key included in Primary Key
    CONSTRAINT pk_traffic_part PRIMARY KEY (reading_id, recorded_at),
    CONSTRAINT fk_traffic_part_segment FOREIGN KEY (segment_id) 
        REFERENCES road_segments(segment_id) ON DELETE CASCADE,
    CONSTRAINT chk_traffic_part_speed CHECK (avg_speed_kmph >= 0.0),
    CONSTRAINT chk_traffic_part_congestion CHECK (
        congestion_level IN ('LOW', 'MODERATE', 'HEAVY', 'STANDSTILL')
    )
) PARTITION BY RANGE (recorded_at);

-- Generate monthly partitions for traffic_readings using PL/pgSQL
DO $traffic_parts$
DECLARE
    curr_start TIMESTAMPTZ := '2025-01-01 00:00:00+05:30';
    curr_end   TIMESTAMPTZ;
    part_name  TEXT;
BEGIN
    WHILE curr_start < '2027-01-01 00:00:00+05:30' LOOP
        curr_end := curr_start + INTERVAL '1 month';
        part_name := 'traffic_readings_y' || to_char(curr_start, 'YYYY') || 'm' || to_char(curr_start, 'MM');
        
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF traffic_readings_partitioned ' ||
            'FOR VALUES FROM (%L) TO (%L)',
            part_name, curr_start, curr_end
        );
        curr_start := curr_end;
    END LOOP;
END
$traffic_parts$;

CREATE TABLE traffic_readings_default PARTITION OF traffic_readings_partitioned DEFAULT;

-- Local indexes on traffic partitions
CREATE INDEX idx_traffic_part_segment_time 
    ON traffic_readings_partitioned (segment_id, recorded_at DESC);

CREATE INDEX idx_traffic_part_alert 
    ON traffic_readings_partitioned (recorded_at DESC, congestion_level)
    WHERE congestion_level IN ('HEAVY', 'STANDSTILL');

-- ---------------------------------------------------------------------
-- 5. Data Migration from Unpartitioned to Partitioned Tables
-- ---------------------------------------------------------------------

-- Migration helper procedure (idempotent)
INSERT INTO navigation_sessions_partitioned
SELECT * FROM navigation_sessions
ON CONFLICT DO NOTHING;

INSERT INTO traffic_readings_partitioned
SELECT * FROM traffic_readings
ON CONFLICT DO NOTHING;

ANALYZE navigation_sessions_partitioned;
ANALYZE traffic_readings_partitioned;

-- ---------------------------------------------------------------------
-- 6. Verification and Partition Pruning Demonstration
-- Query EXPLAIN plans demonstrating static and dynamic pruning.
-- ---------------------------------------------------------------------

-- Example 1: Query R20 filtered to June 2026.
-- EXPECTED PLAN: Scans ONLY navigation_sessions_y2026m06.
-- All other 23 partitions are PRUNED completely from execution.
EXPLAIN (ANALYZE, BUFFERS)
SELECT started_at::date AS day, count(*) AS sessions
FROM navigation_sessions_partitioned
WHERE started_at >= '2026-06-01 00:00:00+05:30' 
  AND started_at <  '2026-07-01 00:00:00+05:30'
GROUP BY 1
ORDER BY day;

-- Example 2: Query R12 looking at Mumbai destinations in the last 7 days of June 2026.
-- EXPECTED PLAN: Index Scan using idx_nav_part_dest_started on navigation_sessions_y2026m06 only.
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.place_id, p.name, count(*) AS navigations
FROM navigation_sessions_partitioned n
JOIN places p ON p.place_id = n.dest_place_id
WHERE p.city_id = 2
  AND n.started_at >= '2026-06-24 00:00:00+05:30'
  AND n.started_at <  '2026-07-01 00:00:00+05:30'
GROUP BY p.place_id, p.name
ORDER BY navigations DESC
LIMIT 10;

-- Example 3: Live Traffic Alerts (R08) on 30 June 2026 evening.
-- EXPECTED PLAN: Scans only traffic_readings_y2026m06 partition.
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.segment_id, s.road_name, t.recorded_at, t.avg_speed_kmph, t.congestion_level
FROM traffic_readings_partitioned t
JOIN road_segments s ON s.segment_id = t.segment_id
WHERE s.city_id = 1
  AND t.congestion_level IN ('HEAVY', 'STANDSTILL')
  AND t.recorded_at >= '2026-06-30 18:00:00+05:30'
  AND t.recorded_at <= '2026-06-30 23:59:59+05:30'
ORDER BY t.recorded_at DESC;

-- ---------------------------------------------------------------------
-- 7. Operational Maintenance: Automated Partition Provisioning & Archival
-- ---------------------------------------------------------------------

-- Routine to create partitions ahead of time (e.g. invoked monthly via pg_cron)
CREATE OR REPLACE PROCEDURE maintain_navigation_partitions(months_ahead INT DEFAULT 3)
LANGUAGE plpgsql AS $$
DECLARE
    target_month TIMESTAMPTZ;
    next_month   TIMESTAMPTZ;
    p_name       TEXT;
BEGIN
    FOR i IN 1..months_ahead LOOP
        target_month := date_trunc('month', NOW() + (i || ' month')::INTERVAL);
        next_month   := target_month + INTERVAL '1 month';
        p_name       := 'navigation_sessions_y' || to_char(target_month, 'YYYY') || 'm' || to_char(target_month, 'MM');

        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF navigation_sessions_partitioned ' ||
            'FOR VALUES FROM (%L) TO (%L)',
            p_name, target_month, next_month
        );
        RAISE NOTICE 'Verified partition % exists for window [%, %)', p_name, target_month, next_month;
    END LOOP;
END;
$$;

-- Routine for fast data archival (Zero-downtime metadata detachment)
CREATE OR REPLACE PROCEDURE archive_old_navigation_partition(archive_month TIMESTAMPTZ)
LANGUAGE plpgsql AS $$
DECLARE
    p_name TEXT;
BEGIN
    p_name := 'navigation_sessions_y' || to_char(archive_month, 'YYYY') || 'm' || to_char(archive_month, 'MM');
    
    -- In PostgreSQL, DETACH PARTITION is an instantaneous DDL operation.
    -- The detached table can then be dumped to cold Parquet/S3 storage without locking the live system.
    EXECUTE format('ALTER TABLE navigation_sessions_partitioned DETACH PARTITION %I CONCURRENTLY', p_name);
    RAISE NOTICE 'Partition % successfully detached for cold storage archival.', p_name;
END;
$$;
