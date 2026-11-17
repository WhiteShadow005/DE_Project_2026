# Phase 3: Baseline Query Timings

**Database:** `gmaps` · **PostgreSQL version:** 18.6 (Homebrew, aarch64-apple-darwin)  
**Hardware:** MacBook Pro M4 · **Measurement method:** `EXPLAIN (ANALYZE, BUFFERS)`, 3 runs, average reported  
**Benchmark script:** `./benchmarks/run_benchmark.sh gmaps baseline 3`  
**Raw plan files:** `benchmarks/results/baseline/R01.txt` … `W05.txt`

> All queries run with `SET search_path TO gmaps;`. Write queries (W01–W05) run inside `BEGIN … ROLLBACK` so data is not changed.

---

## Timing Table – All 30 Queries

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: "Restaurants near me": open restaurants within ~1 km of Koramangala (12.9352, 77.6245), nearest first | READ | 3.800 | 3.561 | 3.186 | **3.516** |
| R02: Place page: details of place 18 with Tuesday's opening hours | READ | 0.039 | 0.062 | 0.034 | **0.045** |
| R03: Search: Bengaluru places with "biryani" in the name, best rated first | READ | 7.443 | 7.643 | 7.663 | **7.583** |
| R04: "Open now" filter: Bengaluru restaurants open at 23:30 on a Saturday | READ | 8.771 | 9.066 | 9.138 | **8.992** |
| R05: Place page: the 10 newest reviews of place 18 | READ | 0.132 | 0.198 | 0.129 | **0.153** |
| R06: "Saved" tab: user 1005's saved places grouped by list | READ | 0.058 | 0.062 | 0.051 | **0.057** |
| R07: Live traffic layer: latest reading of every Outer Ring Road segment in Bengaluru | READ | 3.605 | 3.543 | 3.611 | **3.586** |
| R08: Traffic alerts: Bengaluru segments with heavy traffic since 18:00 on 30 Jun 2026 | READ | 0.360 | 0.339 | 0.337 | **0.345** |
| R09: "Typical traffic" chart: average speed by hour on segment 5 | READ | 0.233 | 0.205 | 0.194 | **0.211** |
| R10: Incident layer: incidents reported in Bengaluru on 30 Jun 2026 | READ | 0.798 | 0.815 | 0.846 | **0.820** |
| R11: ETA quality: average error per travel mode per month in 2026 | READ | 22.058 | 22.209 | 22.423 | **22.230** |
| R12: Trends: 10 most-navigated-to places in Mumbai in last 7 days of Jun 2026 | READ | 9.358 | 8.910 | 9.965 | **9.411** |
| R13: Data team: places that have never been the starting point of a navigation | READ | 20.636 | 20.001 | 19.931 | **20.189** |
| R14: Local Guides leaderboard: users with most reviews in 2026 | READ | 9.262 | 9.170 | 8.999 | **9.144** |
| R15: Data quality: places whose stored rating/count no longer matches reviews | READ | 32.623 | 39.947 | 33.414 | **35.328** |
| R16: Data quality: permanently closed places navigated to in 2026 | READ | 12.427 | 12.293 | 11.959 | **12.226** |
| R17: Routing team: destinations with most re-routing on average (≥5 trips) | READ | 31.383 | 30.334 | 31.593 | **31.103** |
| R18: Product analytics: share of cancelled navigations per travel mode | READ | 14.323 | 14.416 | 13.978 | **14.239** |
| R19: Health report: every Bengaluru hospital with navigations and most recent one | READ | 13441.721 | 13492.558 | 13493.457 | **13475.912** |
| R20: Product analytics: navigations per day and running total for Jun 2026 | READ | 9.151 | 8.871 | 8.926 | **8.983** |
| R21: Data team: places with no opening hours, counted per category | READ | 19.801 | 20.097 | 20.024 | **19.974** |
| R22: Moderation console: all reviews, newest first, page 2,001 (25 per page) | READ | 14.435 | 14.644 | 14.814 | **14.631** |
| R23: Plus Code search: open the place with code '22222222+2W' | READ | 0.024 | 0.018 | 0.020 | **0.021** |
| R24: Duplicate listings: Bengaluru restaurants with same name within ~100 m | READ | 5.154 | 4.801 | 5.160 | **5.038** |
| R25: Road safety: share of readings above speed limit, per road type | READ | 29.050 | 28.158 | 31.173 | **29.460** |
| W01: "Start": begin navigation from current location to place 18 | WRITE | 0.409 | 0.368 | 0.352 | **0.376** |
| W02: Write a review: user 1005 rates place 18 | WRITE | 0.370 | 0.352 | 0.343 | **0.355** |
| W03: "Save": user 1005 adds place 18 to "Want to go" | WRITE | 0.398 | 0.366 | 0.333 | **0.366** |
| W04: Nightly job: recompute every place's rating and review count | WRITE | 29.132 | 28.253 | 28.675 | **28.687** |
| W05: Housekeeping: delete incident reports that expired before Jun 2026 | WRITE | 1.973 | 2.014 | 2.107 | **2.031** |
| **Total (sum of all 30)** | | **13617.079** | **13757.722** | **13745.705** | **13706.671** |

---

## Scan Type & Why Fast / Slow

| Query | Scan Type | Why slow / fast |
|-------|-----------|-----------------|
| R01 | **Seq Scan** on `places` | No index on `(category_id, latitude, longitude)` — scans all 40k rows and computes trig per row |
| R02 | Index Scan on `places_pkey`, `opening_hours_pkey` | PK lookups on a single row — fast by design |
| R03 | **Seq Scan** on `places` | `ILIKE '%biryani%'` cannot use a B-tree; scans all 40k rows |
| R04 | **Seq Scan** on `opening_hours` + `places` | No index on `(city_id, category_id)`; full scans to filter then join |
| R05 | Bitmap Heap Scan on `place_reviews` via `uq_user_place_review` | UNIQUE index covers `(place_id, user_id)` but not `created_at` — partial heap scan |
| R06 | Index Scan on `saved_places_pkey` | PK on `(user_id, place_id, list_name)` — first column equality, fast |
| R07 | Bitmap Heap Scan on `traffic_readings` via `uq_segment_recorded_at` | Index exists but must fetch 125 rows per segment × 40 segments; lots of random I/O |
| R08 | Seq Scan on `road_segments`, Index Scan on `uq_segment_recorded_at` | No partial index for heavy/standstill; scans all readings after 18:00 |
| R09 | Bitmap Heap Scan on `traffic_readings` | Only 125 rows for segment 5; small result set so very fast |
| R10 | **Seq Scan** on `incident_reports` + `road_segments` | `DATE(reported_at)` function call disables index use; city filter needs road_segments scan |
| R11 | **Seq Scan** on `navigation_sessions` | `EXTRACT(YEAR FROM started_at)` wraps column in function; full 200k-row scan |
| R12 | **Seq Scan** on `navigation_sessions` + `places` | No index on `started_at`; city filter on places requires full scan |
| R13 | **Seq Scan** on `places` + `navigation_sessions` | `NOT IN (SELECT origin_place_id …)` with NULLs: **wrong-answer bug** (NULLs make NOT IN return no rows — but here origin_place_id NULLs cause the subquery to include NULL, making NOT IN return empty set for all places — 33 368 rows returned only because NULLs are excluded from NOT IN comparison) |
| R14 | **Seq Scan** on `place_reviews` + `users` | Full join of 90k reviews to 40k users, then aggregate |
| R15 | **Seq Scan** on `place_reviews` + `places` | Full join + GROUP BY + HAVING; must read entire reviews table |
| R16 | **Seq Scan** on `navigation_sessions` + `places` | No index on `is_permanently_closed`; full scans |
| R17 | **Seq Scan** on `navigation_sessions` | Full 200k-row aggregate on `dest_place_id` with HAVING |
| R18 | **Seq Scan** on `navigation_sessions` | Full table aggregate; unavoidable but no index helps grouping |
| R19 | **Seq Scan** on `place_categories`, `places`, `navigation_sessions` (**×1067 correlated subqueries**) | Correlated subqueries execute once per hospital row (1067 hospitals in Bengaluru) — **13.5 s** |
| R20 | **Seq Scan** on `navigation_sessions` | No index on `started_at`; scans 200k rows for June filter |
| R21 | **Seq Scan** on `opening_hours` + `places` + `place_categories` | Anti-join via NOT EXISTS scans all 252k opening_hours rows |
| R22 | **Seq Scan** on `place_reviews` | `OFFSET 50000` forces reading and discarding 50k rows |
| R23 | Index Scan on `places_plus_code_key` | UNIQUE index on `plus_code` — single row lookup, 0.021 ms |
| R24 | **Seq Scan** on `places` (self-join) | Self-join on `name` + coordinate filter; 40k × 40k but bounding box reduces it |
| R25 | **Seq Scan** on `traffic_readings` + `road_segments` | Full join of 250k readings × 2k segments; no index helps aggregate |
| W01 | (no scan) — INSERT | PK check only — fast |
| W02 | (no scan) — INSERT with ON CONFLICT | Unique index check only — fast |
| W03 | (no scan) — INSERT with ON CONFLICT | PK check only — fast |
| W04 | **Seq Scan** on `places` + `place_reviews` | Full aggregate of all reviews + full scan of places for UPDATE |
| W05 | **Seq Scan** on `incident_reports` | No index on `expires_at`; scans all 12k rows |

---

## Key Findings

1. **R19 is the worst query at 13.5 s** — correlated subqueries run 1067 × for Bengaluru hospitals. Rewriting with a JOIN or CTE will collapse this to < 10 ms.
2. **R13 has a subtle NULL bug**: `NOT IN (SELECT origin_place_id …)` returns empty when any `origin_place_id` is NULL (192 584 out of 200 000 sessions have NULL origin). The correct rewrite uses `NOT EXISTS`.
3. **R03/R24 need GIN trigram indexes** for `ILIKE` searches.
4. **R10/R11/R20 use functions on indexed columns** (`DATE(col)`, `EXTRACT(YEAR FROM col)`, `col::date`) making those columns non-sargable. Rewrites use range predicates.
5. **R07 is slow due to DISTINCT ON** needing to sort 5048 rows; a covering index on `(segment_id, recorded_at DESC)` eliminates the sort.
6. **R15 and W04 are unavoidable full-table reads** but can be sped up with a composite index on `place_reviews(place_id, rating)`.
