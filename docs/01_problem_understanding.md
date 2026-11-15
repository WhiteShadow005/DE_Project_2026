# Phase 1: Problem Understanding & Stakeholder Analysis

**Project:** Google Maps Navigation Database (India Region)  
**Team:** T0010 (ReguFlow) · **Section:** D  
**Contributors:** Ashwin Maurya (2501010099), Arnav Gupta (2501010080), Shaurya Pratap Singh (2501010591, @sps-exe), Yashvardhan Mundhra (2501010527)  

---

## 1. Problem Statements Breakdown & Stakeholder Mapping

| ID | Operational Problem Reported | Primary Stakeholders | System Category | Associated Workload Queries | Business Need & Technical Impact |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **P1** | **"Near me" & "Open now" search latency**, especially across midnight-crossing business hours. | **Travellers, Drivers, Local Diners, Search Engineering Team** | **Customer-Facing / Real-Time** | `R01`, `R03`, `R04`, `R23` | High-frequency geospatial lookups (bounding-box / Haversine distance) and temporal opening-hour evaluation. Latency directly harms consumer mobile conversion and navigation start times. Sub-50ms response is critical. |
| **P2** | **Place Page details, reviews, and Saved lists lagging** on mobile clients. | **App Users, Business Owners, Places Engineering Team** | **Customer-Facing / Real-Time** | `R02`, `R05`, `R06`, `W02`, `W03` | Core engagement surface. Users loading a Point of Interest (POI) require place attributes, current day hours, newest reviews, and personal saved-list status without pagination lag or lock contention during review writes. |
| **P3** | **Live traffic layer and incident feeds** failing to refresh at 1-minute cadence. | **Navigating Drivers, Commuters, Traffic Monitoring Team** | **Customer-Facing / Real-Time** | `R07`, `R08`, `R10`, `W05` | Dynamic situational awareness. The routing engine and live map overlay require real-time aggregation of the latest speed readings and active hazard/roadwork reports per road segment. Slow reads produce stale routing decisions. |
| **P4** | **"Typical traffic" baseline calculations and road safety compliance** reports timing out. | **Urban Planners, Traffic Analytics Team, Municipal Authorities** | **Reporting / Analytics** | `R09`, `R25` | Heavy analytical aggregations calculating historical hourly velocity profiles across road types and speed-limit exceedance ratios. High-volume aggregation queries over millions of readings that must not block operational traffic ingestion. |
| **P5** | **Routing team ETA inaccuracy, re-routing hotspot analysis**, and slow navigation initiation. | **Drivers, Commuters, Routing / ETA Algorithms Team** | **Customer-Facing (W01) & Analytics (R11, R12, R17, R18)** | `R11`, `R12`, `R17`, `R18`, `W01` | Starting navigation must write immediately ($< 10$ms). Concurrently, backend routing models require historical variance analysis (actual vs ETA minutes), hotspot re-route clustering, and travel-mode cancellation ratios to tune predictive ETA engines. |
| **P6** | **"Places never navigated from" data quality report returning empty**, concealing dead POIs. | **Data Engineering Team, POI Operations** | **Reporting / Analytics** | `R13` | Data integrity audit query bug: A classic SQL anti-join defect (`NOT IN (SELECT origin_place_id ...)`) returning zero rows due to `NULL` values in the origin column. Needs a robust `NOT EXISTS` or `LEFT JOIN / IS NULL` rewrite to surface truly unvisited places. |
| **P7** | **Data quality integrity checks timing out** (stale rating aggregates, closed places visited, missing hours). | **Data Quality Audit Team, Platform Operations** | **Reporting / Analytics** | `R15`, `R16`, `R21`, `R24`, `W04` | Audit jobs scanning for discrepancies between denormalized counters (`avg_rating`, `review_count`) and actual `place_reviews` rows, finding active trips to permanently closed places, and flagging duplicate POIs within 100m. |
| **P8** | **Moderation consoles, Local Guides leaderboards, and system health checks lagging** under 20× growth. | **Community Moderation Team, Local Guides, Growth Executives** | **Reporting / Analytics** | `R14`, `R19`, `R20`, `R22` | Heavy aggregations ranking top contributors, computing running cumulative navigation totals, scanning deep review pages (offset 50,000+), and evaluating hospital emergency access. Subqueries currently trigger multi-second sequential table scans. |

---

## 2. Performance Classification & Latency Targets

* **Tier 1: Customer-Facing / Real-Time (SLA: $< 50$ ms)**
  * Includes `P1` (Search & Open Now), `P2` (Place Pages & Saved Lists), `P3` (Live Traffic & Incidents), and navigation session creation (`W01`).
  * *Target:* Optimized composite B-Tree indexes, partial indexes on active traffic jams, and covering index scans.
* **Tier 2: Reporting & Analytics (SLA: $< 500$ ms for interactive dashboard; batch overnight acceptable)**
  * Includes `P4` (Typical Traffic), `P5` (Routing Model Evaluation), `P6` (Unused POI Audits), `P7` (Catalog Health Checks), and `P8` (Community Leaderboards & Scalability).
  * *Target:* Aggregation restructuring, elimination of correlated subqueries, partition pruning, and sargable predicates.

---

## 3. Core Architectural Assumptions

1. **Schema Namespace Isolation**: All production tables reside strictly within the dedicated `gmaps` schema to isolate navigational workloads from public database objects.
2. **Temporal & Midnight Business Crossovers**: Opening hours with `closes < opens` represent valid overnight operations (e.g. 18:00 to 02:00) rather than invalid inputs.
3. **Guest & GPS Origin Sessions**: Navigation sessions with `user_id IS NULL` represent unauthenticated guest users; sessions with `origin_place_id IS NULL` represent trips initiated directly from raw GPS device coordinates rather than a cataloged POI.
4. **Denormalization Justification**: Columns `places.avg_rating` and `places.review_count` are intentional performance caches designed to protect mobile place lookups from expensive real-time aggregations over `place_reviews`. Nightly maintenance (`W04`) reconciles drift.
5. **No Tuning in Phase 2**: The CP1 baseline database strictly relies on Primary Key, Foreign Key, Unique, and Check constraints. Secondary performance tuning (B-Tree, Partial, GIN) is deferred to Phase 4 (CP3).
