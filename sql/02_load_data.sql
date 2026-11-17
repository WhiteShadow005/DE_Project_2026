-- =====================================================================
-- Google Maps Navigation Database: Data Ingestion & Integrity Checks (Phase 2 / CP1)
-- Target RDBMS: PostgreSQL 15+
-- Schema: gmaps
-- 
-- Execution:
--   psql -d <database_name> -f sql/02_load_data.sql
-- 
-- Note:
--   Make sure seed_data.zip has been extracted into the project root
--   so that the relative path 'seed_data/*.csv' resolves correctly.
-- =====================================================================

SET search_path TO gmaps;

\echo '---------------------------------------------------------------------'
\echo 'Starting bulk data ingestion in foreign key dependency order...'
\echo '---------------------------------------------------------------------'

-- 1. Master lookup tables (no foreign dependencies)
\echo 'Loading cities...'
\copy cities FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading place_categories...'
\copy place_categories FROM 'seed_data/place_categories.csv' WITH (FORMAT csv, HEADER true)

-- 2. Master entities
\echo 'Loading users...'
\copy users FROM 'seed_data/users.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading places...'
\copy places FROM 'seed_data/places.csv' WITH (FORMAT csv, HEADER true)

-- 3. Dependent place and user relational tables
\echo 'Loading opening_hours...'
\copy opening_hours FROM 'seed_data/opening_hours.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading place_reviews...'
\copy place_reviews FROM 'seed_data/place_reviews.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading saved_places...'
\copy saved_places FROM 'seed_data/saved_places.csv' WITH (FORMAT csv, HEADER true)

-- 4. Road network and telemetry
\echo 'Loading road_segments...'
\copy road_segments FROM 'seed_data/road_segments.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading traffic_readings...'
\copy traffic_readings FROM 'seed_data/traffic_readings.csv' WITH (FORMAT csv, HEADER true)

-- 5. Navigation sessions and incident logs
\echo 'Loading navigation_sessions...'
\copy navigation_sessions FROM 'seed_data/navigation_sessions.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading incident_reports...'
\copy incident_reports FROM 'seed_data/incident_reports.csv' WITH (FORMAT csv, HEADER true)

\echo '---------------------------------------------------------------------'
\echo 'Bulk ingestion complete. Running ANALYZE on all tables...'
\echo '---------------------------------------------------------------------'

ANALYZE;

\echo '---------------------------------------------------------------------'
\echo 'Verifying ingested row counts across all 11 tables:'
\echo '---------------------------------------------------------------------'

SELECT 'cities' AS table_name, count(*) AS row_count, 10 AS expected_rows FROM cities
UNION ALL
SELECT 'place_categories', count(*), 12 FROM place_categories
UNION ALL
SELECT 'users', count(*), 40000 FROM users
UNION ALL
SELECT 'places', count(*), 40042 FROM places
UNION ALL
SELECT 'opening_hours', count(*), 252266 FROM opening_hours
UNION ALL
SELECT 'place_reviews', count(*), 89998 FROM place_reviews
UNION ALL
SELECT 'saved_places', count(*), 50000 FROM saved_places
UNION ALL
SELECT 'road_segments', count(*), 2000 FROM road_segments
UNION ALL
SELECT 'traffic_readings', count(*), 250000 FROM traffic_readings
UNION ALL
SELECT 'navigation_sessions', count(*), 200000 FROM navigation_sessions
UNION ALL
SELECT 'incident_reports', count(*), 12000 FROM incident_reports
ORDER BY table_name;

\echo '---------------------------------------------------------------------'
\echo 'Integrity Check 1: Denormalized rating & review count consistency'
\echo '---------------------------------------------------------------------'
-- Compares places.avg_rating and places.review_count with aggregated place_reviews
WITH review_stats AS (
    SELECT 
        place_id,
        count(*) AS actual_reviews,
        round(avg(rating)::numeric, 2) AS actual_avg
    FROM place_reviews
    GROUP BY place_id
)
SELECT 
    count(*) AS total_mismatches,
    count(*) FILTER (WHERE p.review_count != COALESCE(rs.actual_reviews, 0)) AS count_mismatches,
    count(*) FILTER (WHERE p.avg_rating != COALESCE(rs.actual_avg, 0.00)) AS rating_mismatches
FROM places p
LEFT JOIN review_stats rs ON p.place_id = rs.place_id
WHERE p.review_count != COALESCE(rs.actual_reviews, 0)
   OR p.avg_rating != COALESCE(rs.actual_avg, 0.00);

\echo '---------------------------------------------------------------------'
\echo 'Integrity Check 2: Origin coordinate alignment with origin_place_id'
\echo '---------------------------------------------------------------------'
-- When a navigation session specifies origin_place_id, verifies that origin coordinates match the place
SELECT 
    count(*) AS total_named_origin_trips,
    count(*) FILTER (
        WHERE abs(ns.origin_lat - p.latitude) > 0.0001 
           OR abs(ns.origin_lng - p.longitude) > 0.0001
    ) AS coordinate_discrepancies
FROM navigation_sessions ns
JOIN places p ON ns.origin_place_id = p.place_id
WHERE ns.origin_place_id IS NOT NULL;

\echo '---------------------------------------------------------------------'
\echo 'Integrity Check 3: Incident expiration validity and road connectivity'
\echo '---------------------------------------------------------------------'
-- Verifies that all incidents have positive durations and link to valid urban segments
SELECT 
    count(*) AS total_incidents,
    count(*) FILTER (WHERE ir.expires_at <= ir.reported_at) AS invalid_expiry_count,
    count(*) FILTER (WHERE rs.segment_id IS NULL) AS orphaned_incident_count
FROM incident_reports ir
LEFT JOIN road_segments rs ON ir.segment_id = rs.segment_id;
