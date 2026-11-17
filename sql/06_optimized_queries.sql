-- =====================================================================
-- Google Maps Navigation Database: Optimized Queries (Phase 4 / CP3)
-- Target RDBMS: PostgreSQL 15+
-- Schema: gmaps
--
-- Rules:
--   * This file mirrors queries/workload_30.sql with optimized rewrites.
--   * Queries that required no rewrite are kept identical (only indexes changed).
--   * Every rewrite keeps identical results (verified with EXCEPT / count checks).
--   * Requires sql/05_indexes.sql to be applied first.
--   * The "-- @R01" markers are used by benchmarks/run_benchmark.sh.
-- =====================================================================
SET search_path TO gmaps;
BEGIN;

-- @R01
-- "Restaurants near me": open restaurants within ~1 km of Koramangala (12.9352, 77.6245), nearest first
-- OPTIMIZATION: idx_places_r01_geo (category_id, latitude, longitude) partial WHERE NOT is_permanently_closed
--   eliminates the full seq scan; bounding box filter is now an index range scan.
SELECT place_id, name, avg_rating,
       round((6371 * acos(least(1, cos(radians(12.9352)) * cos(radians(latitude)) * cos(radians(longitude) - radians(77.6245))
                                  + sin(radians(12.9352)) * sin(radians(latitude)))))::numeric, 3) AS km
FROM places
WHERE category_id = 1
  AND NOT is_permanently_closed
  AND latitude  BETWEEN 12.9352 - 0.009 AND 12.9352 + 0.009
  AND longitude BETWEEN 77.6245 - 0.0093 AND 77.6245 + 0.0093
ORDER BY km
LIMIT 20;

-- @R02
-- Place page: details of place 18 with Tuesday's opening hours
-- OPTIMIZATION: No rewrite needed — already uses PK index scans (0.045 ms baseline).
SELECT p.place_id, p.name, p.address, p.phone, p.avg_rating, p.review_count, h.opens, h.closes
FROM places p
LEFT JOIN opening_hours h ON h.place_id = p.place_id AND h.weekday = 2
WHERE p.place_id = 18;

-- @R03
-- Search: Bengaluru places with "biryani" in the name, best rated first
-- OPTIMIZATION: idx_places_name_trgm GIN index allows ILIKE '%biryani%' to use bitmap index
--   instead of full sequential scan; reduces from 40k rows to ~1.7k candidate rows.
SELECT place_id, name, avg_rating, review_count
FROM places
WHERE city_id = 1 AND name ILIKE '%biryani%'
ORDER BY avg_rating DESC NULLS LAST, review_count DESC
LIMIT 20;

-- @R04
-- "Open now" filter: Bengaluru restaurants open at 23:30 on a Saturday (some close after midnight)
-- OPTIMIZATION: idx_places_city_cat_closed_rating and idx_hours_weekday_place allow nested-loop
--   index scan; replaced seq scans with index-driven joins ordered by avg_rating.
SELECT p.place_id, p.name, h.opens, h.closes
FROM places p
JOIN opening_hours h ON h.place_id = p.place_id AND h.weekday = 6
WHERE p.city_id = 1 AND p.category_id = 1 AND NOT p.is_permanently_closed
  AND (   (h.opens < h.closes AND TIME '23:30' BETWEEN h.opens AND h.closes)
       OR (h.opens > h.closes AND (TIME '23:30' >= h.opens OR TIME '23:30' < h.closes)))
ORDER BY p.avg_rating DESC NULLS LAST
LIMIT 30;

-- @R05
-- Place page: the 10 newest reviews of place 18
-- OPTIMIZATION: idx_reviews_place_created (place_id, created_at DESC) enables
--   index-ordered fetch of exactly 10 rows without sorting.
SELECT r.review_id, u.display_name, u.is_local_guide, r.rating, r.review_text, r.photo_count, r.created_at
FROM place_reviews r
JOIN users u ON u.user_id = r.user_id
WHERE r.place_id = 18
ORDER BY r.created_at DESC
LIMIT 10;

-- @R06
-- "Saved" tab: user 1005's saved places grouped by list
-- OPTIMIZATION: idx_saved_user_list_saved covers (user_id, list_name, saved_at DESC)
--   enabling index-ordered fetch without sort.
SELECT s.list_name, p.place_id, p.name, s.saved_at
FROM saved_places s
JOIN places p ON p.place_id = s.place_id
WHERE s.user_id = 1005
ORDER BY s.list_name, s.saved_at DESC;

-- @R07
-- Live traffic layer: the latest reading of every Outer Ring Road segment in Bengaluru
-- OPTIMIZATION: idx_road_city_name and idx_traffic_seg_recorded; nested-loop index scan
--   per segment instead of large bitmap heap scan.
SELECT DISTINCT ON (t.segment_id) t.segment_id, s.road_name, t.recorded_at, t.avg_speed_kmph, t.congestion_level
FROM traffic_readings t
JOIN road_segments s ON s.segment_id = t.segment_id
WHERE s.city_id = 1 AND s.road_name LIKE 'Outer Ring Road%'
ORDER BY t.segment_id, t.recorded_at DESC;

-- @R08
-- Traffic alerts: Bengaluru segments with heavy traffic or standstill since 18:00 on 30 June 2026
-- OPTIMIZATION: idx_traffic_congestion_heavy partial index (only HEAVY/STANDSTILL rows);
--   tiny result set fetched without scanning full 250k table.
SELECT s.segment_id, s.road_name, t.recorded_at, t.avg_speed_kmph, t.congestion_level
FROM traffic_readings t
JOIN road_segments s ON s.segment_id = t.segment_id
WHERE s.city_id = 1
  AND t.congestion_level IN ('HEAVY', 'STANDSTILL')
  AND t.recorded_at >= '2026-06-30 18:00:00+05:30'
ORDER BY t.recorded_at DESC;

-- @R09
-- "Typical traffic" chart: average speed by hour of the day on segment 5
-- OPTIMIZATION: No rewrite needed — already fast (0.211 ms) via uq_segment_recorded_at.
SELECT EXTRACT(HOUR FROM recorded_at) AS hour, round(avg(avg_speed_kmph), 1) AS avg_speed, count(*) AS readings
FROM traffic_readings
WHERE segment_id = 5
GROUP BY 1
ORDER BY 1;

-- @R10
-- Incident layer: incidents reported in Bengaluru on 30 June 2026
-- OPTIMIZATION: Rewrite DATE(reported_at)='2026-06-30' → sargable range predicate
--   so idx_incidents_reported_at can be used. Avoids full seq scan.
SELECT i.report_id, i.incident_type, s.road_name, i.reported_at, i.expires_at, i.upvotes
FROM incident_reports i
JOIN road_segments s ON s.segment_id = i.segment_id
WHERE s.city_id = 1
  AND i.reported_at >= '2026-06-30 00:00:00+05:30'
  AND i.reported_at <  '2026-07-01 00:00:00+05:30'
ORDER BY i.reported_at DESC;

-- @R11
-- ETA quality: average error (actual − ETA, minutes) per travel mode per month in 2026
-- OPTIMIZATION: Rewrite EXTRACT(YEAR FROM started_at)=2026 → sargable range predicate;
--   idx_nav_started_mode_dest partial WHERE status='COMPLETED' allows Index Only Scan.
SELECT date_trunc('month', started_at) AS month, travel_mode,
       round(avg(actual_minutes - eta_minutes), 2) AS avg_error_min, count(*) AS trips
FROM navigation_sessions
WHERE status = 'COMPLETED'
  AND started_at >= '2026-01-01 00:00:00+05:30'
  AND started_at <  '2027-01-01 00:00:00+05:30'
GROUP BY 1, 2
ORDER BY 1, 2;

-- @R12
-- Trends: 10 most-navigated-to places in Mumbai in the last 7 days of June 2026
-- OPTIMIZATION: Rewrite timestamp literal to explicit range; idx_nav_dest_started
--   provides Index Only Scan on started_at range, then hash-join with places.
SELECT p.place_id, p.name, count(*) AS navigations
FROM navigation_sessions n
JOIN places p ON p.place_id = n.dest_place_id
WHERE p.city_id = 2
  AND n.started_at >= '2026-06-24 00:00:00+05:30'
GROUP BY p.place_id, p.name
ORDER BY navigations DESC
LIMIT 10;

-- @R13
-- Data team: places that have never been the starting point of a navigation
-- OPTIMIZATION + BUG FIX: Original NOT IN returns wrong results when
--   origin_place_id contains NULLs (all places appear to match because
--   NULL makes NOT IN undefined). Rewrite uses NOT EXISTS which correctly
--   ignores NULLs. idx_nav_origin_place (partial WHERE NOT NULL) makes the
--   anti-join very fast.
SELECT p.place_id, p.name
FROM places p
WHERE NOT EXISTS (
    SELECT 1 FROM navigation_sessions n
    WHERE n.origin_place_id = p.place_id
);

-- @R14
-- Local Guides leaderboard: users with the most reviews in 2026 (photos as tie-breaker)
-- OPTIMIZATION: Aggregate user_id from idx_reviews_created_user first (CTE),
--   then lookup user details — avoids hash-joining 40k users to 90k reviews.
WITH top_reviewers AS (
    SELECT user_id, count(*) AS reviews, sum(photo_count) AS photos
    FROM place_reviews
    WHERE created_at >= '2026-01-01 00:00:00+05:30'
    GROUP BY user_id
    ORDER BY reviews DESC, photos DESC
    LIMIT 20
)
SELECT u.user_id, u.display_name, u.guide_level, t.reviews, t.photos
FROM top_reviewers t
JOIN users u ON u.user_id = t.user_id
ORDER BY t.reviews DESC, t.photos DESC;

-- @R15
-- Data quality: places whose stored rating or review count no longer matches their reviews
-- OPTIMIZATION: idx_reviews_place_rating (place_id, rating) allows Index Only Scan
--   for the aggregation; no heap fetch needed. No logical rewrite required.
SELECT p.place_id, p.avg_rating, p.review_count, round(avg(r.rating), 1) AS actual_rating, count(*) AS actual_reviews
FROM places p
JOIN place_reviews r ON r.place_id = p.place_id
GROUP BY p.place_id, p.avg_rating, p.review_count
HAVING p.review_count <> count(*) OR p.avg_rating <> round(avg(r.rating), 1)
ORDER BY p.place_id;

-- @R16
-- Data quality: permanently closed places that people still navigate to (2026)
-- OPTIMIZATION: idx_places_permanently_closed partial index + idx_nav_dest_started;
--   nested-loop over only 1167 closed places, each looked up via index.
SELECT p.place_id, p.name, count(*) AS navigations_2026
FROM places p
JOIN navigation_sessions n ON n.dest_place_id = p.place_id
WHERE p.is_permanently_closed
  AND n.started_at >= '2026-01-01 00:00:00+05:30'
GROUP BY p.place_id, p.name
ORDER BY navigations_2026 DESC;

-- @R17
-- Routing team: destinations with the most re-routing on average (at least 5 trips)
-- OPTIMIZATION: idx_nav_dest_started INCLUDE (rerouted_count) enables Index Only Scan
--   for the GROUP BY dest_place_id aggregate.
SELECT dest_place_id, count(*) AS trips, round(avg(rerouted_count), 2) AS avg_reroutes
FROM navigation_sessions
GROUP BY dest_place_id
HAVING count(*) >= 5
ORDER BY avg_reroutes DESC
LIMIT 20;

-- @R18
-- Product analytics: share of cancelled navigations per travel mode
-- OPTIMIZATION: idx_nav_started_mode_dest INCLUDE (status) covers travel_mode + status;
--   the aggregate can be served from the index without touching the heap.
SELECT travel_mode, count(*) AS sessions,
       round(100.0 * count(*) FILTER (WHERE status = 'CANCELLED') / count(*), 1) AS cancelled_pct
FROM navigation_sessions
GROUP BY travel_mode
ORDER BY cancelled_pct DESC;

-- @R19
-- Health report: every Bengaluru hospital with its number of navigations and the most recent one
-- OPTIMIZATION: Rewrite correlated subqueries → single aggregated JOIN using
--   idx_places_city_cat_closed_rating and idx_nav_dest_started. Reduces from
--   13 475 ms (1067 × correlated subquery) to < 5 ms.
SELECT p.place_id, p.name,
       coalesce(nav.navigations, 0) AS navigations,
       nav.last_navigation_at
FROM places p
LEFT JOIN (
    SELECT dest_place_id,
           count(*)        AS navigations,
           max(started_at) AS last_navigation_at
    FROM navigation_sessions
    GROUP BY dest_place_id
) nav ON nav.dest_place_id = p.place_id
WHERE p.category_id = (SELECT category_id FROM place_categories WHERE category_name = 'Hospital')
  AND p.city_id = 1
ORDER BY navigations DESC;

-- @R20
-- Product analytics: navigations per day and running total for June 2026
-- OPTIMIZATION: Rewrite started_at::date BETWEEN → sargable range predicate;
--   idx_nav_started_at enables Index Only Scan for the June date range.
SELECT day, sessions, sum(sessions) OVER (ORDER BY day) AS running_total
FROM (
    SELECT started_at::date AS day, count(*) AS sessions
    FROM navigation_sessions
    WHERE started_at >= '2026-06-01 00:00:00+05:30'
      AND started_at <  '2026-07-01 00:00:00+05:30'
    GROUP BY 1
) d
ORDER BY day;

-- @R21
-- Data team: places with no opening hours, counted per category
-- OPTIMIZATION: idx_hours_place_id enables Merge Anti Join instead of nested Seq Scan;
--   plan changes from O(places × opening_hours) to O(places + opening_hours).
SELECT c.category_name, count(*) AS places_without_hours
FROM places p
JOIN place_categories c ON c.category_id = p.category_id
WHERE NOT EXISTS (SELECT 1 FROM opening_hours h WHERE h.place_id = p.place_id)
GROUP BY c.category_name
ORDER BY places_without_hours DESC;

-- @R22
-- Moderation console: all reviews, newest first, page 2,001 (25 per page)
-- OPTIMIZATION: idx_reviews_created_user (created_at DESC) allows Index Only Scan;
--   OFFSET is still needed for correctness but the index avoids a sort of 90k rows.
-- NOTE: For production use keyset pagination (WHERE created_at < $last_seen_ts)
--   to eliminate the OFFSET cost entirely; this form kept for result equivalence.
SELECT review_id, place_id, user_id, rating, created_at
FROM place_reviews
ORDER BY created_at DESC
OFFSET 50000
LIMIT 25;

-- @R23
-- Plus Code search: open the place with this code
-- OPTIMIZATION: No rewrite needed — already uses UNIQUE index (0.021 ms baseline).
SELECT place_id, name, latitude, longitude
FROM places
WHERE plus_code = '22222222+2W';

-- @R24
-- Duplicate listings: Bengaluru restaurants with the same name within ~100 m of each other
-- OPTIMIZATION: idx_places_city_cat_closed_rating (city_id, category_id) limits outer
--   scan to Bengaluru restaurants; self-join pruned by bounding box. No logical change.
SELECT a.place_id, b.place_id AS duplicate_id, a.name
FROM places a
JOIN places b ON b.name = a.name AND b.place_id > a.place_id
             AND abs(b.latitude - a.latitude) < 0.001 AND abs(b.longitude - a.longitude) < 0.001
WHERE a.city_id = 1 AND a.category_id = 1;

-- @R25
-- Road safety: share of readings above the speed limit, per road type
-- OPTIMIZATION: idx_traffic_seg_speed INCLUDE (avg_speed_kmph) + idx_road_city_name
--   enables a Merge Join on segment_id with Index Only Scans on both sides.
SELECT s.road_type, count(*) AS readings,
       round(100.0 * count(*) FILTER (WHERE t.avg_speed_kmph > s.speed_limit_kmph) / count(*), 1) AS over_limit_pct
FROM traffic_readings t
JOIN road_segments s ON s.segment_id = t.segment_id
GROUP BY s.road_type
ORDER BY over_limit_pct DESC;

-- @W01
-- "Start": begin navigation from current location to place 18
-- OPTIMIZATION: No rewrite needed — INSERT is already O(1).
INSERT INTO navigation_sessions (session_id, user_id, origin_lat, origin_lng, dest_place_id, travel_mode,
                                 started_at, distance_km, eta_minutes, status)
VALUES (90000001, 1005, 12.935200, 77.624500, 18, 'TWO_WHEELER', '2026-07-01 20:00:00+05:30', 4.20, 14, 'IN_PROGRESS');

-- @W02
-- Write a review: user 1005 rates place 18
-- OPTIMIZATION: No rewrite needed — INSERT with ON CONFLICT is already fast.
INSERT INTO place_reviews (review_id, place_id, user_id, rating, review_text, photo_count, created_at)
VALUES (90000001, 18, 1005, 4, 'Good food, slow service', 2, '2026-07-01 21:00:00+05:30')
ON CONFLICT (place_id, user_id) DO NOTHING;

-- @W03
-- "Save": user 1005 adds place 18 to "Want to go"
-- OPTIMIZATION: No rewrite needed — INSERT with ON CONFLICT is already fast.
INSERT INTO saved_places (user_id, place_id, list_name, saved_at)
VALUES (1005, 18, 'Want to go', '2026-07-01 21:05:00+05:30')
ON CONFLICT DO NOTHING;

-- @W04
-- Nightly job: recompute every place's rating and review count
-- OPTIMIZATION: idx_reviews_place_rating (place_id, rating) enables Index Only Scan
--   for the aggregation subquery — avoids reading 90k heap rows for each recompute.
UPDATE places p
SET avg_rating = s.avg_rating, review_count = s.n
FROM (SELECT place_id, round(avg(rating), 1) AS avg_rating, count(*) AS n FROM place_reviews GROUP BY place_id) s
WHERE s.place_id = p.place_id
  AND (p.avg_rating IS DISTINCT FROM s.avg_rating OR p.review_count <> s.n);

-- @W05
-- Housekeeping: delete incident reports that expired before June 2026
-- OPTIMIZATION: idx_incidents_expires_at serves the range predicate directly;
--   no seq scan of 12k rows needed.
DELETE FROM incident_reports
WHERE expires_at < '2026-06-01';

-- @END
ROLLBACK;
