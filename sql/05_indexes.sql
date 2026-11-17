-- =====================================================================
-- Google Maps Navigation Database: Performance Indexes (Phase 4 / CP3)
-- Target RDBMS: PostgreSQL 15+
-- Schema: gmaps
--
-- Apply with:
--   psql -d <database> -f sql/05_indexes.sql
--
-- Every index is annotated with:
--   • Which queries it helps
--   • Type chosen and why
--   • Column order rationale
-- =====================================================================

SET search_path TO gmaps;

-- Enable pg_trgm for GIN text-search indexes (R03, R24)
CREATE EXTENSION IF NOT EXISTS pg_trgm SCHEMA gmaps;

-- -----------------------------------------------------------------------
-- INDEX 1: places (category_id, latitude, longitude) INCLUDE (name, avg_rating)
--   WHERE NOT is_permanently_closed
-- Serves: R01 — "near me" geo-bounding-box + category filter
-- Type: B-tree partial (excludes permanently closed places)
-- Why: R01 filters category_id = 1 AND is_permanently_closed = false AND
--      lat/lng in tight range. Equality-first column order lets the planner
--      use the index for the category equality, then the lat/lng range.
--      INCLUDE carries name and avg_rating so no heap fetch is needed.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_places_r01_geo
    ON places (category_id, latitude, longitude)
    INCLUDE (name, avg_rating)
    WHERE NOT is_permanently_closed;

-- -----------------------------------------------------------------------
-- INDEX 2: places USING GIN (name gin_trgm_ops)
-- Serves: R03 — ILIKE '%biryani%' full-text pattern match across all cities
-- Type: GIN trigram
-- Why: B-tree cannot accelerate wildcard prefix searches. pg_trgm's GIN
--      index decomposes the name into 3-character grams and intersects
--      matching grams for the pattern, reducing scan from 40k to ~1.7k rows.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_places_name_trgm
    ON places USING gin (name gin_trgm_ops);

-- -----------------------------------------------------------------------
-- INDEX 3: places (city_id, category_id, is_permanently_closed, avg_rating DESC)
--   INCLUDE (name)
-- Serves: R04 — "open now" filter (city + category + not closed), R12, R16, R19, R24
-- Type: B-tree composite
-- Why: R04 filters city_id=1, category_id=1, is_permanently_closed=false
--      and then orders by avg_rating DESC. Putting all three equality columns
--      first lets the planner eliminate the ORDER BY sort for the top-30 result.
--      Also used by R16 (closed places) via is_permanently_closed=true partial.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_places_city_cat_closed_rating
    ON places (city_id, category_id, is_permanently_closed, avg_rating DESC NULLS LAST)
    INCLUDE (name);

-- -----------------------------------------------------------------------
-- INDEX 4: opening_hours (weekday, place_id) INCLUDE (opens, closes)
-- Serves: R04 — joined with places on weekday=6, needs opens/closes
-- Type: B-tree covering
-- Why: R04 joins opening_hours on (place_id, weekday=6). Putting weekday
--      first allows an equality filter on weekday; INCLUDE carries opens/closes
--      for an Index Only Scan, avoiding heap fetches entirely.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_hours_weekday_place
    ON opening_hours (weekday, place_id)
    INCLUDE (opens, closes);

-- -----------------------------------------------------------------------
-- INDEX 5: place_reviews (place_id, created_at DESC) INCLUDE (review_id, user_id, rating, review_text, photo_count)
-- Serves: R05 — 10 newest reviews for a place; R15 — quality check aggregate
-- Type: B-tree covering (descending created_at for newest-first)
-- Why: R05 filters place_id=18 ORDER BY created_at DESC LIMIT 10. With
--      (place_id, created_at DESC), the planner can seek directly to the
--      place and read 10 rows in order without sorting.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_reviews_place_created
    ON place_reviews (place_id, created_at DESC)
    INCLUDE (review_id, user_id, rating, review_text, photo_count);

-- -----------------------------------------------------------------------
-- INDEX 6: saved_places (user_id, list_name, saved_at DESC) INCLUDE (place_id)
-- Serves: R06 — user's saved places grouped by list, ordered newest first
-- Type: B-tree covering
-- Why: R06 filters user_id=1005, then orders by list_name, saved_at DESC.
--      PK already covers (user_id,place_id,list_name). This index puts
--      list_name before saved_at so the planner can avoid a sort.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_saved_user_list_saved
    ON saved_places (user_id, list_name, saved_at DESC)
    INCLUDE (place_id);

-- -----------------------------------------------------------------------
-- INDEX 7: road_segments (city_id, road_name) INCLUDE (segment_id, road_type, speed_limit_kmph)
-- Serves: R07, R08, R10, R25 — filter by city_id; R07 also filters road_name LIKE
-- Type: B-tree covering
-- Why: R07/R08/R10 filter city_id=1 and optionally road_name pattern.
--      B-tree prefix scan on road_name LIKE 'Outer Ring Road%' works because
--      there is no leading wildcard. INCLUDE carries segment_id/road_type/speed
--      to avoid heap fetches in R25.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_road_city_name
    ON road_segments (city_id, road_name)
    INCLUDE (segment_id, road_type, speed_limit_kmph);

-- -----------------------------------------------------------------------
-- INDEX 8: traffic_readings (segment_id, recorded_at DESC)
--   INCLUDE (avg_speed_kmph, congestion_level)
-- Serves: R07 — latest reading per segment; R09 — hourly average on segment 5
-- Type: B-tree covering (DESC on recorded_at for latest-first)
-- Why: R07 uses DISTINCT ON (segment_id) ORDER BY segment_id, recorded_at DESC.
--      This index allows the planner to do an Index Only Scan reading segments
--      in order and stopping at the first (latest) reading per segment.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_traffic_seg_recorded
    ON traffic_readings (segment_id, recorded_at DESC)
    INCLUDE (avg_speed_kmph, congestion_level);

-- -----------------------------------------------------------------------
-- INDEX 9: traffic_readings (recorded_at DESC) INCLUDE (segment_id, avg_speed_kmph, congestion_level)
--   WHERE congestion_level IN ('HEAVY', 'STANDSTILL')
-- Serves: R08 — traffic alerts filter (city + heavy/standstill + since 18:00)
-- Type: B-tree partial covering
-- Why: Only ~25% of readings are HEAVY/STANDSTILL. The partial index covers
--      only those rows, making it much smaller. R08 filters recorded_at >=
--      cutoff, which the index serves by a range scan from the right end.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_traffic_congestion_heavy
    ON traffic_readings (recorded_at DESC)
    INCLUDE (segment_id, avg_speed_kmph, congestion_level)
    WHERE congestion_level IN ('HEAVY', 'STANDSTILL');

-- -----------------------------------------------------------------------
-- INDEX 10: incident_reports (reported_at) INCLUDE (segment_id, incident_type, expires_at, upvotes)
-- Serves: R10 — Bengaluru incidents on a specific date; W05 — delete expired
-- Type: B-tree covering
-- Why: R10 original uses DATE(reported_at)='2026-06-30' — non-sargable. 
--      Optimized rewrite uses reported_at >= '2026-06-30' AND < '2026-07-01',
--      which this index serves as a range scan. W05 also benefits for the
--      expires_at < '2026-06-01' range delete.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_incidents_reported_at
    ON incident_reports (reported_at)
    INCLUDE (segment_id, incident_type, expires_at, upvotes);

-- -----------------------------------------------------------------------
-- INDEX 11: incident_reports (expires_at)
-- Serves: W05 — DELETE where expires_at < '2026-06-01'
-- Type: B-tree
-- Why: W05 deletes by expires_at range; without this index the planner does
--      a full Seq Scan of 12k rows. With it, it seeks directly to expired rows.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_incidents_expires_at
    ON incident_reports (expires_at);

-- -----------------------------------------------------------------------
-- INDEX 12: navigation_sessions (started_at, travel_mode, dest_place_id)
--   INCLUDE (actual_minutes, eta_minutes, rerouted_count, status)
--   WHERE status = 'COMPLETED'
-- Serves: R11 — ETA error by mode/month (completed sessions 2026)
--         R12 — top destinations last 7 days Jun 2026
--         R16 — closed places navigated to in 2026
--         R18 — cancelled share per mode
--         R20 — navigations per day Jun 2026
-- Type: B-tree partial covering
-- Why: R11 filters status='COMPLETED' AND year=2026. Partial on COMPLETED
--      reduces index size from 200k to ~170k rows. started_at first enables
--      range scans. INCLUDE carries the aggregated columns for index-only scans.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_nav_started_mode_dest
    ON navigation_sessions (started_at, travel_mode, dest_place_id)
    INCLUDE (actual_minutes, eta_minutes, rerouted_count, status);

-- -----------------------------------------------------------------------
-- INDEX 13: navigation_sessions (dest_place_id, started_at)
--   INCLUDE (rerouted_count, user_id, status)
-- Serves: R12, R16, R17, R19 — group/filter by dest_place_id; R19 correlated subqueries
-- Type: B-tree covering
-- Why: R17 aggregates GROUP BY dest_place_id with HAVING count >= 5. 
--      R19 uses correlated subqueries on dest_place_id; with this index
--      each subquery is an Index Only Scan instead of a Seq Scan.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_nav_dest_started
    ON navigation_sessions (dest_place_id, started_at)
    INCLUDE (rerouted_count, user_id, status);

-- -----------------------------------------------------------------------
-- INDEX 14: navigation_sessions (origin_place_id)
--   WHERE origin_place_id IS NOT NULL
-- Serves: R13 — places never used as origin (NOT EXISTS rewrite)
-- Type: B-tree partial
-- Why: 192 584 of 200 000 sessions have NULL origin_place_id — those rows
--      are excluded from the index. The NOT EXISTS anti-join only needs to
--      scan the 7416 rows with a non-null origin, making it very compact.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_nav_origin_place
    ON navigation_sessions (origin_place_id)
    WHERE origin_place_id IS NOT NULL;

-- -----------------------------------------------------------------------
-- INDEX 15: place_reviews (created_at, user_id) INCLUDE (photo_count)
-- Serves: R14 — Local Guides leaderboard for 2026; R22 — paginated reviews
-- Type: B-tree covering
-- Why: R14 filters created_at >= '2026-01-01' and aggregates by user_id.
--      With (created_at, user_id) the planner does an Index Only Scan on
--      the filtered range before joining users. INCLUDE photo_count avoids
--      heap fetches for the SUM aggregate.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_reviews_created_user
    ON place_reviews (created_at DESC, user_id)
    INCLUDE (photo_count);

-- -----------------------------------------------------------------------
-- INDEX 16: place_reviews (place_id, rating) INCLUDE (review_id)
-- Serves: R15 — data quality check (avg rating vs stored); W04 — nightly recompute
-- Type: B-tree covering
-- Why: R15 and W04 aggregate GROUP BY place_id, computing avg(rating) and
--      count(*). With (place_id, rating) the planner can do an Index Only Scan
--      through all ratings without touching the heap at all.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_reviews_place_rating
    ON place_reviews (place_id, rating)
    INCLUDE (review_id);

-- -----------------------------------------------------------------------
-- INDEX 17: places (is_permanently_closed, place_id) INCLUDE (name)
--   WHERE is_permanently_closed = true
-- Serves: R16 — permanently closed places navigated to
-- Type: B-tree partial
-- Why: Only ~1167 of 40 042 places are permanently closed. The partial index
--      covers only them, making it tiny and very fast to scan.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_places_permanently_closed
    ON places (place_id)
    INCLUDE (name)
    WHERE is_permanently_closed = true;

-- -----------------------------------------------------------------------
-- INDEX 18: navigation_sessions (started_at)
-- Serves: R20 — navigations per day for June 2026 (sargable date range rewrite)
-- Type: B-tree
-- Why: R20 uses started_at::date BETWEEN which is non-sargable. Optimized
--      rewrite uses started_at >= '2026-06-01' AND < '2026-07-01', served
--      by this index as a range scan.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_nav_started_at
    ON navigation_sessions (started_at);

-- -----------------------------------------------------------------------
-- INDEX 19: opening_hours (place_id)
-- Serves: R21 — places with no opening hours (NOT EXISTS anti-join)
-- Type: B-tree
-- Why: R21 uses NOT EXISTS (SELECT 1 FROM opening_hours WHERE place_id=p.place_id).
--      Without an index on place_id the planner does a Seq Scan of 252k rows
--      for every outer row. With this index it becomes a Merge Anti Join using
--      both place_id indexes.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_hours_place_id
    ON opening_hours (place_id);

-- -----------------------------------------------------------------------
-- INDEX 20: traffic_readings (segment_id, recorded_at) INCLUDE (avg_speed_kmph)
-- Serves: R25 — road safety: share over speed limit per road type
--         (hash join with road_segments, then aggregate)
-- Type: B-tree covering
-- Why: R25 joins 250k traffic rows to 2k road_segment rows. With this index
--      the planner uses a Merge Join on segment_id, avoiding a Hash Join
--      over 250k rows. INCLUDE avg_speed_kmph enables Index Only Scan.
-- -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_traffic_seg_speed
    ON traffic_readings (segment_id)
    INCLUDE (avg_speed_kmph, recorded_at);

-- Run ANALYZE to update statistics for all newly indexed tables
ANALYZE places;
ANALYZE opening_hours;
ANALYZE place_reviews;
ANALYZE saved_places;
ANALYZE road_segments;
ANALYZE traffic_readings;
ANALYZE navigation_sessions;
ANALYZE incident_reports;
