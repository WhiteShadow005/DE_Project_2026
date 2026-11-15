# Schema Design: Google Maps Navigation Database

**Project:** Google Maps Navigation Database (India Region)  
**Team:** T0010 (ReguFlow) · **Section:** D · **Phase:** 2 / CP1  
**PostgreSQL Version:** 16  
**Schema Namespace:** `gmaps`

---

## 1. Data Dictionary — All 11 Tables

### 1.1 `cities` — Urban Metropolitan Areas

| Column | Data Type | Constraints | Justification |
| :--- | :--- | :--- | :--- |
| `city_id` | `INTEGER` | `PRIMARY KEY` | Synthetic numeric surrogate; small stable lookup table (10 rows). |
| `city_name` | `VARCHAR(100)` | `NOT NULL` | City names (Bengaluru, Mumbai…). Max observed length: ~15 chars. |
| `center_lat` | `DECIMAL(9,6)` | `NOT NULL`, `CHECK (BETWEEN -90 AND 90)` | 6 decimal places = ~11 cm precision. India latitudes: 8°N–36°N. |
| `center_lng` | `DECIMAL(9,6)` | `NOT NULL`, `CHECK (BETWEEN -180 AND 180)` | India longitudes: 68°E–97°E. Decimal vs FLOAT avoids rounding artefacts. |

**Cardinalities:** 1 city → N places, N road segments, N users (home city).

---

### 1.2 `place_categories` — Point-of-Interest Classification

| Column | Data Type | Constraints | Justification |
| :--- | :--- | :--- | :--- |
| `category_id` | `INTEGER` | `PRIMARY KEY` | Stable numeric surrogate. 12 categories in seed data. |
| `category_name` | `VARCHAR(100)` | `NOT NULL`, `UNIQUE` | Natural candidate key. Names: Restaurant, Cafe, Hospital, ATM, Petrol Pump, Hotel, Pharmacy, Shopping Mall, Park, Metro Station, School, Supermarket. |

**Cardinalities:** 1 category → N places.

---

### 1.3 `users` — Registered Accounts & Local Guides

| Column | Data Type | Constraints | Justification |
| :--- | :--- | :--- | :--- |
| `user_id` | `INTEGER` | `PRIMARY KEY` | Synthetic surrogate. 40,000 rows. |
| `display_name` | `VARCHAR(150)` | `NOT NULL` | Visible public handle. Never empty in seed data. |
| `email` | `VARCHAR(255)` | `NOT NULL`, `UNIQUE` | Natural candidate key. Standard email max = 254 chars. No duplicates verified. |
| `home_city_id` | `INTEGER` | `FOREIGN KEY → cities(city_id) ON DELETE SET NULL` | Optional home-city association. SET NULL preserves user records if a city is ever removed (unlikely but safe). |
| `is_local_guide` | `BOOLEAN` | `NOT NULL DEFAULT FALSE` | Distinguishes verified content contributors from regular users. |
| `guide_level` | `INTEGER` | `CHECK: guide_level 1-10 when local_guide=true, else NULL` | Business rule: only Local Guides hold levels. Verified against full dataset — 0 non-guides with a level value. |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL` | Account creation timestamp with timezone (IST +05:30 observed in seed data). |

**Cardinalities:** 1 user → N reviews, N saved places, N navigation sessions (optional), N incident reports (optional).

---

### 1.4 `places` — Points of Interest (Core Entity)

| Column | Data Type | Constraints | Justification |
| :--- | :--- | :--- | :--- |
| `place_id` | `INTEGER` | `PRIMARY KEY` | Synthetic surrogate. 40,042 rows. |
| `plus_code` | `VARCHAR(30)` | `NOT NULL`, `UNIQUE` | Google Plus Codes are globally unique location codes (format: `XXXXXXXX+YY`). Verified 0 duplicates in seed data. Used in `R23` (direct lookup). |
| `name` | `VARCHAR(255)` | `NOT NULL` | POI display name. Used in trigram substring search (`R03`). |
| `category_id` | `INTEGER` | `NOT NULL`, `FOREIGN KEY → place_categories ON DELETE RESTRICT` | RESTRICT prevents orphaned POIs if a category is removed. Category is mandatory — no uncategorised places in data. |
| `city_id` | `INTEGER` | `NOT NULL`, `FOREIGN KEY → cities ON DELETE RESTRICT` | Every POI belongs to exactly one city. RESTRICT prevents city deletion while POIs exist. |
| `latitude` | `DECIMAL(9,6)` | `NOT NULL`, `CHECK (BETWEEN -90 AND 90)` | Observed range in seed data: 12.82°N to 28.76°N (all within India). |
| `longitude` | `DECIMAL(9,6)` | `NOT NULL`, `CHECK (BETWEEN -180 AND 180)` | Observed range: 72.42°E to 88.51°E. |
| `address` | `TEXT` | `NOT NULL` | Full postal address string. Unbounded length (TEXT) due to variable Indian address formats. |
| `phone` | `VARCHAR(30)` | `NULL allowed` | Optional landline/mobile. Some POIs (parks, roads) have no phone. |
| `website` | `VARCHAR(255)` | `NULL allowed` | Optional URL. Many small POIs have no web presence. |
| `price_level` | `INTEGER` | `CHECK (1-4 or NULL)` | 1=inexpensive to 4=very expensive. Only relevant for commercial venues; NULL for hospitals, parks, government offices. |
| `avg_rating` | `DECIMAL(3,2)` | `NOT NULL DEFAULT 0.00`, `CHECK (0.00-5.00)` | Denormalized cache of aggregate from `place_reviews`. Maintained by nightly `W04` job. Rating 0.00 means unreviewed (not "bad"). |
| `review_count` | `INTEGER` | `NOT NULL DEFAULT 0`, `CHECK (≥ 0)` | Denormalized review count cache. Synchronized by `W04`. |
| `is_permanently_closed` | `BOOLEAN` | `NOT NULL DEFAULT FALSE` | Soft-delete flag. Closed places retained for navigational history analysis (`R16`). |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL` | POI publication timestamp. |

**Cardinalities:** 1 place → N opening_hours, N reviews, N saved_places. Places appear as origin (optional) or destination (required) in navigation_sessions.

**Derived Column Justification:** `avg_rating` and `review_count` are intentional denormalizations. Without them, every place-page load would require a full aggregate scan of 90,000 `place_reviews` rows. The nightly `W04` reconciliation job corrects any drift.

---

### 1.5 `opening_hours` — Weekly Operating Schedules

| Column | Data Type | Constraints | Justification |
| :--- | :--- | :--- | :--- |
| `place_id` | `INTEGER` | `PRIMARY KEY (composite)`, `FOREIGN KEY → places ON DELETE CASCADE` | Cascades deletion: removing a place automatically removes its hours. |
| `weekday` | `INTEGER` | `PRIMARY KEY (composite)`, `CHECK (1-7)` | ISO weekday: 1=Monday, 7=Sunday. No duplicates found (0 violations in 252,266 rows). |
| `opens` | `TIME` | `NOT NULL` | Opening time, no timezone (local wall-clock time). |
| `closes` | `TIME` | `NOT NULL` | Closing time. When `closes < opens`, the venue operates overnight (crosses midnight). The schema deliberately permits this (e.g., 23:00–02:00). |

**Data Anomaly Found:** No anomalies. Composite PK `(place_id, weekday)` is enforced and confirmed unique across all 252,266 rows. Midnight-crossover rows are valid business data (see `R04` — "open at 23:30 on a Saturday").

---

### 1.6 `place_reviews` — User Ratings and Reviews

| Column | Data Type | Constraints | Justification |
| :--- | :--- | :--- | :--- |
| `review_id` | `INTEGER` | `PRIMARY KEY` | Synthetic surrogate. 89,998 rows. |
| `place_id` | `INTEGER` | `NOT NULL`, `FOREIGN KEY → places ON DELETE CASCADE`, `UNIQUE(place_id, user_id)` | Cascade: deleting a place removes its reviews. One review per user per place (business policy, confirmed 0 duplicates). |
| `user_id` | `INTEGER` | `NOT NULL`, `FOREIGN KEY → users ON DELETE CASCADE` | Reviews are tied to accounts. ON DELETE CASCADE: when a user deletes their account, reviews go too. |
| `rating` | `INTEGER` | `NOT NULL`, `CHECK (1-5)` | 1-star to 5-star scale. Distinct from `places.avg_rating` (which is a computed aggregate). |
| `review_text` | `TEXT` | `NULL allowed` | Optional narrative text — ratings without text are valid ("star-only" reviews). |
| `photo_count` | `INTEGER` | `NOT NULL DEFAULT 0`, `CHECK (≥ 0)` | Number of attached photos. 0 is valid (text-only review). |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL` | Review submission timestamp. |

**Cardinalities:** M:N relationship between `users` and `places`, resolved through `place_reviews`. The `UNIQUE(place_id, user_id)` constraint enforces one review per user per venue policy.

---

### 1.7 `saved_places` — Personal Bookmark Lists

| Column | Data Type | Constraints | Justification |
| :--- | :--- | :--- | :--- |
| `user_id` | `INTEGER` | `PRIMARY KEY (composite)`, `FOREIGN KEY → users ON DELETE CASCADE` | Part of 3-column composite PK. Cascade: clearing a user account removes their bookmarks. |
| `place_id` | `INTEGER` | `PRIMARY KEY (composite)`, `FOREIGN KEY → places ON DELETE CASCADE` | Part of composite PK. |
| `list_name` | `VARCHAR(100)` | `PRIMARY KEY (composite)`, `CHECK (IN 'Want to go', 'Starred', 'Favourites', 'Travel plans')` | Users can save the same place into different lists. The 3-column composite PK prevents duplicate entries within the same list. Allowed values verified exhaustively in seed data. |
| `saved_at` | `TIMESTAMPTZ` | `NOT NULL` | When the bookmark was created. |

**Cardinalities:** M:N between `users` and `places`, resolved by `saved_places`. A single (user, place) pair can appear in multiple lists (hence 3-column PK).

---

### 1.8 `road_segments` — Street & Highway Network

| Column | Data Type | Constraints | Justification |
| :--- | :--- | :--- | :--- |
| `segment_id` | `INTEGER` | `PRIMARY KEY` | Synthetic surrogate. ~1,000 road segments. |
| `road_name` | `VARCHAR(200)` | `NOT NULL` | Named road identifier (e.g., "MG Road (Segment 2)"). Long names possible for complex intersections. |
| `city_id` | `INTEGER` | `NOT NULL`, `FOREIGN KEY → cities ON DELETE RESTRICT` | Each segment belongs to exactly one urban area. RESTRICT prevents city removal while road data exists. |
| `road_type` | `VARCHAR(50)` | `NOT NULL`, `CHECK (IN 'ARTERIAL', 'LOCAL', 'HIGHWAY')` | Three observed types in full seed data. Influences speed limits and query filters (`R25`). |
| `start_lat`, `start_lng` | `DECIMAL(9,6)` | `NOT NULL`, coordinate range checks | Geometric start point of segment. |
| `end_lat`, `end_lng` | `DECIMAL(9,6)` | `NOT NULL`, coordinate range checks | Geometric end point of segment. |
| `length_m` | `INTEGER` | `NOT NULL`, `CHECK (> 0)` | Segment physical length in meters. Must be positive. |
| `speed_limit_kmph` | `INTEGER` | `NOT NULL`, `CHECK (> 0)` | Posted speed limit. Used in R25 (speeding detection). Must be positive and non-zero. |

**Cardinalities:** 1 road_segment → N traffic_readings, N incident_reports.

---

### 1.9 `traffic_readings` — Real-Time Speed Telemetry

| Column | Data Type | Constraints | Justification |
| :--- | :--- | :--- | :--- |
| `reading_id` | `INTEGER` | `PRIMARY KEY` | Synthetic surrogate. 250,000 rows. |
| `segment_id` | `INTEGER` | `NOT NULL`, `FOREIGN KEY → road_segments ON DELETE CASCADE` | Each reading belongs to a segment. Cascade: removing a segment purges its telemetry history. |
| `recorded_at` | `TIMESTAMPTZ` | `NOT NULL`, `UNIQUE(segment_id, recorded_at)` | Composite unique: one reading per segment per timestamp (no duplicate telemetry). Verified 0 duplicates. |
| `avg_speed_kmph` | `DECIMAL(6,2)` | `NOT NULL`, `CHECK (≥ 0)` | Measured vehicular speed. 0 valid (standstill). Two decimal places capture precise speed. |
| `congestion_level` | `VARCHAR(30)` | `NOT NULL`, `CHECK (IN 'LOW', 'MODERATE', 'HEAVY', 'STANDSTILL')` | Derived categorical label. Only 3 levels observed in full 250,000-row dataset (LOW, MODERATE, HEAVY). STANDSTILL included as valid future business value. |

**Data Anomaly Found:** `congestion_level` could be derived from `avg_speed_kmph` vs `road_segments.speed_limit_kmph`. It is kept as a stored column because: (1) the routing engine needs instant categorical access without joining road_segments, and (2) congestion classification involves hysteresis logic (not a simple threshold) that is applied upstream by the telemetry ingestion pipeline.

---

### 1.10 `navigation_sessions` — Trip Logs (Largest Table)

| Column | Data Type | Constraints | Justification |
| :--- | :--- | :--- | :--- |
| `session_id` | `INTEGER` | `PRIMARY KEY` | Synthetic surrogate. 200,000 rows. |
| `user_id` | `INTEGER` | `NULL allowed`, `FOREIGN KEY → users ON DELETE SET NULL` | NULL = guest navigation (40,275 rows / 20% of trips). ON DELETE SET NULL preserves trip history when accounts are deleted. |
| `origin_place_id` | `INTEGER` | `NULL allowed`, `FOREIGN KEY → places ON DELETE SET NULL` | NULL = navigation started from raw GPS coordinates (192,584 rows / 96%). This is the dominant pattern — most trips don't originate from catalogued POIs. The `NOT IN (origin_place_id)` anti-join in `R13` returns 0 rows due to these NULLs — a known SQL defect requiring a `NOT EXISTS` rewrite. |
| `origin_lat`, `origin_lng` | `DECIMAL(9,6)` | `NOT NULL`, coordinate range checks | Always present (GPS coordinates captured even for POI origins). |
| `dest_place_id` | `INTEGER` | `NOT NULL`, `FOREIGN KEY → places ON DELETE RESTRICT` | Destination is always a catalogued POI (required for navigation). RESTRICT: cannot delete a place that is an active destination. |
| `travel_mode` | `VARCHAR(30)` | `NOT NULL`, `CHECK (IN 'DRIVE', 'TRANSIT', 'WALK', 'TWO_WHEELER')` | Four modes observed in full dataset. |
| `started_at` | `TIMESTAMPTZ` | `NOT NULL` | Trip initiation timestamp. |
| `distance_km` | `DECIMAL(8,2)` | `NOT NULL`, `CHECK (≥ 0)` | Planned route distance. |
| `eta_minutes` | `INTEGER` | `NOT NULL`, `CHECK (> 0)` | Estimated trip duration at time of start. Always positive. |
| `actual_minutes` | `INTEGER` | `CHECK: NOT NULL when COMPLETED, NULL when CANCELLED` | Actual trip duration. NULL for cancelled trips (they never finished). Verified: 0 completed trips with NULL actual_minutes, 0 cancelled trips with non-NULL actual_minutes. |
| `rerouted_count` | `INTEGER` | `NOT NULL DEFAULT 0`, `CHECK (≥ 0)` | Number of routing recalculations during trip. |
| `status` | `VARCHAR(30)` | `NOT NULL`, `CHECK (IN 'COMPLETED', 'CANCELLED')` | Only two statuses in full 200,000-row dataset. |

**Cardinalities:** 1 user → N sessions (optional). 1 place → N sessions as origin (optional) or destination (required). The large volume of NULL origin_place_id is structurally significant for query correctness in R13.

---

### 1.11 `incident_reports` — Crowdsourced Hazard Reports

| Column | Data Type | Constraints | Justification |
| :--- | :--- | :--- | :--- |
| `report_id` | `INTEGER` | `PRIMARY KEY` | Synthetic surrogate. 12,000 rows. |
| `segment_id` | `INTEGER` | `NOT NULL`, `FOREIGN KEY → road_segments ON DELETE CASCADE` | Incidents are tied to specific road segments. Cascade: removing a segment removes its incident history. |
| `user_id` | `INTEGER` | `NULL allowed`, `FOREIGN KEY → users ON DELETE SET NULL` | Incidents can be submitted by anonymous reporters or automated sensors (NULL user_id). |
| `incident_type` | `VARCHAR(50)` | `NOT NULL`, `CHECK (IN 'ROADWORK', 'POLICE', 'CLOSURE', 'WATERLOGGING', 'ACCIDENT', 'BREAKDOWN', 'HAZARD')` | 6 types observed in full 12,000-row dataset. HAZARD added as a valid future operational category. |
| `reported_at` | `TIMESTAMPTZ` | `NOT NULL` | Incident observation timestamp. |
| `expires_at` | `TIMESTAMPTZ` | `NOT NULL`, `CHECK (expires_at > reported_at)` | TTL-based automatic expiration. All 12,000 rows pass this check (0 violations). Incidents must expire after they are reported. |
| `upvotes` | `INTEGER` | `NOT NULL DEFAULT 0`, `CHECK (≥ 0)` | Community corroboration count. Can be 0 (new unverified report). Cannot go negative. |

---

## 2. ER Diagram

The entity-relationship diagram is saved at [`diagrams/er_diagram.svg`](../diagrams/er_diagram.svg).

### Entity Cardinality Summary

```
cities          ||--o{ places              : "1 city has N places"
cities          ||--o{ road_segments       : "1 city has N road segments"
cities          ||--o{ users               : "1 city is home to N users (optional)"
place_categories||--o{ places              : "1 category applies to N places"
places          ||--o{ opening_hours       : "1 place has N weekly hour records"
places          ||--o{ place_reviews       : "1 place receives N reviews"
places          ||--o{ saved_places        : "1 place saved in N user lists"
places          |o--o{ navigation_sessions : "1 place is optional origin in N sessions"
places          ||--o{ navigation_sessions : "1 place is required destination in N sessions"
users           ||--o{ place_reviews       : "1 user authors N reviews"
users           ||--o{ saved_places        : "1 user has N bookmarks"
users           |o--o{ navigation_sessions : "1 user (or guest) starts N sessions"
users           |o--o{ incident_reports    : "1 user (or anon) files N reports"
road_segments   ||--o{ traffic_readings    : "1 segment has N telemetry readings"
road_segments   ||--o{ incident_reports    : "1 segment has N incident reports"
```

---

## 3. Functional Dependencies & Normalization Proof

### 3.1 `cities`
- FDs: `city_id → {city_name, center_lat, center_lng}`
- **3NF/BCNF:** Single-column PK. No transitive dependencies. ✅

### 3.2 `place_categories`
- FDs: `category_id → category_name`; `category_name → category_id` (bidirectional)
- **3NF/BCNF:** Both columns are candidate keys of each other. ✅

### 3.3 `users`
- FDs: `user_id → {display_name, email, home_city_id, is_local_guide, guide_level, created_at}`; `email → user_id` (candidate key)
- Potential concern: `is_local_guide → guide_level` (multi-valued dependency)?
  - This is a conditional constraint enforced via CHECK, not a separate repeating group. The table is in BCNF because every determinant is a superkey. ✅
- **3NF/BCNF:** ✅

### 3.4 `places`
- FDs: `place_id → {all columns}`; `plus_code → place_id` (candidate key)
- Redundant columns: `avg_rating` and `review_count` are computable from `place_reviews`. Retained as a justified denormalization cache (see Section 1.4). These are not 3NF violations since they don't create transitive dependencies through non-prime attributes — they are explicitly managed derived values.
- `congestion_level` is NOT in this table. `traffic_readings.congestion_level` is similarly justified.
- **3NF:** ✅ (with documented denormalization)

### 3.5 `opening_hours`
- FDs: `{place_id, weekday} → {opens, closes}`
- Composite PK = composite candidate key. No partial dependencies (both columns in PK are needed to determine times). No transitive dependencies.
- **3NF/BCNF:** ✅

### 3.6 `place_reviews`
- FDs: `review_id → {all columns}`; `{place_id, user_id} → {rating, review_text, photo_count, created_at}` (composite candidate key)
- No transitive dependencies through non-prime attributes.
- **3NF/BCNF:** ✅

### 3.7 `saved_places`
- FDs: `{user_id, place_id, list_name} → saved_at`
- 3-column composite PK is the minimal candidate key. No non-prime attributes determine other non-prime attributes.
- **3NF/BCNF:** ✅

### 3.8 `road_segments`
- FDs: `segment_id → {all columns}`
- No transitive dependencies.
- **3NF/BCNF:** ✅

### 3.9 `traffic_readings`
- FDs: `reading_id → {all columns}`; `{segment_id, recorded_at} → {all columns}` (composite candidate key)
- `congestion_level` could theoretically be derived from `avg_speed_kmph` and `road_segments.speed_limit_kmph`, but classification involves upstream hysteresis logic and is not a simple functional dependency within this table alone. Retained as stored column. Not a 3NF violation.
- **3NF/BCNF:** ✅

### 3.10 `navigation_sessions`
- FDs: `session_id → {all columns}`
- `actual_minutes` is conditionally dependent on `status` (NULL iff CANCELLED). This is enforced via CHECK constraint, not a table-level FD violation.
- `eta_minutes` could theoretically be derived from `distance_km` and `travel_mode` but requires dynamic traffic data — not a stored deterministic FD.
- **3NF/BCNF:** ✅

### 3.11 `incident_reports`
- FDs: `report_id → {all columns}`
- No transitive dependencies.
- **3NF/BCNF:** ✅

---

## 4. Data Quality Findings from Seed Data Analysis

| Table | Anomaly Found | Root Cause | Schema Decision |
| :--- | :--- | :--- | :--- |
| `navigation_sessions` | 96% of rows have `origin_place_id = NULL` | Most trips start from real-time GPS, not a catalogued POI | Allow NULL; documented as expected business behaviour. |
| `navigation_sessions` | 20% of rows have `user_id = NULL` | Guest users (unauthenticated navigations) | Allow NULL with `ON DELETE SET NULL`. |
| `places` | `avg_rating = 0.00` for unreviewed places | No reviews exist yet — not a data error | 0.00 is valid, represents "unrated". |
| `traffic_readings` | `congestion_level` only has 3 values (LOW, MODERATE, HEAVY) despite STANDSTILL being a valid business state | Seed data doesn't include extreme jam scenarios | CHECK constraint includes STANDSTILL for future real data. |
| `incident_reports` | 6 incident types observed; `HAZARD` absent in seed data | Seed data only covers common urban incidents | HAZARD added to CHECK constraint as a valid future type. |
| `opening_hours` | `closes < opens` on some rows | Overnight/midnight-crossover venues (e.g., 22:00–02:00) | Intentional. Schema allows it. Query R04 must handle this correctly. |

---

## 5. Integrity Check Results (Post-Load Validation)

The following integrity queries are automated in `sql/02_load_data.sql` and must return 0 violations after loading:

| Check ID | Query Description | Expected Result |
| :--- | :--- | :--- |
| **IC-1** | Count of places where `avg_rating` or `review_count` does not match aggregation from `place_reviews`. | 0 mismatches (seed data is consistent at load time) |
| **IC-2** | Count of navigation sessions with `origin_place_id IS NOT NULL` where `origin_lat/lng` deviates more than 0.0001 degrees from the referenced place's coordinates. | 0 discrepancies |
| **IC-3** | Count of incident reports where `expires_at <= reported_at` or `segment_id` has no matching road segment. | 0 violations |

> **Note:** The IC-1 check will begin reporting mismatches after `W02` (write review) or `W03` (save place) operations accumulate without a corresponding `W04` (nightly recompute). This is expected production drift behavior, not a schema defect.
