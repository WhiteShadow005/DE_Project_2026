-- =====================================================================
-- Google Maps Navigation Database: Schema Definition (Phase 2 / CP1)
-- Target RDBMS: PostgreSQL 15+
-- Schema: gmaps
-- 
-- Rules:
-- 1. Strict relational data types matching seed data exports.
-- 2. Clean Primary Key and Foreign Key constraints with justified ON DELETE rules.
-- 3. Comprehensive business CHECK constraints (20+ constraints).
-- 4. NO manual secondary performance indexes created in this phase (CP1 baseline).
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS gmaps;
SET search_path TO gmaps;

-- Drop tables in reverse dependency order for clean re-execution
DROP TABLE IF EXISTS incident_reports CASCADE;
DROP TABLE IF EXISTS navigation_sessions CASCADE;
DROP TABLE IF EXISTS traffic_readings CASCADE;
DROP TABLE IF EXISTS road_segments CASCADE;
DROP TABLE IF EXISTS saved_places CASCADE;
DROP TABLE IF EXISTS place_reviews CASCADE;
DROP TABLE IF EXISTS opening_hours CASCADE;
DROP TABLE IF EXISTS places CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS place_categories CASCADE;
DROP TABLE IF EXISTS cities CASCADE;

-- ---------------------------------------------------------------------
-- 1. Table: cities
-- Master catalog of served urban metropolitan areas in India.
-- ---------------------------------------------------------------------
CREATE TABLE cities (
    city_id INTEGER PRIMARY KEY,
    city_name VARCHAR(100) NOT NULL,
    center_lat DECIMAL(9, 6) NOT NULL,
    center_lng DECIMAL(9, 6) NOT NULL,
    CONSTRAINT chk_cities_lat CHECK (center_lat BETWEEN -90.0 AND 90.0),
    CONSTRAINT chk_cities_lng CHECK (center_lng BETWEEN -180.0 AND 180.0)
);

-- ---------------------------------------------------------------------
-- 2. Table: place_categories
-- Classification hierarchy for Points of Interest (Restaurants, Hospitals, etc.)
-- ---------------------------------------------------------------------
CREATE TABLE place_categories (
    category_id INTEGER PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL UNIQUE
);

-- ---------------------------------------------------------------------
-- 3. Table: users
-- Registered Google Maps accounts, reviewers, and Local Guides.
-- ---------------------------------------------------------------------
CREATE TABLE users (
    user_id INTEGER PRIMARY KEY,
    display_name VARCHAR(150) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    home_city_id INTEGER,
    is_local_guide BOOLEAN NOT NULL DEFAULT FALSE,
    guide_level INTEGER,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_users_city FOREIGN KEY (home_city_id) 
        REFERENCES cities(city_id) ON DELETE SET NULL,
    CONSTRAINT chk_users_guide_level CHECK (
        (is_local_guide = TRUE AND guide_level BETWEEN 1 AND 10) OR
        (is_local_guide = FALSE AND guide_level IS NULL)
    )
);

-- ---------------------------------------------------------------------
-- 4. Table: places
-- Points of interest (POIs) with geolocation, metadata, and rating caches.
-- ---------------------------------------------------------------------
CREATE TABLE places (
    place_id INTEGER PRIMARY KEY,
    plus_code VARCHAR(30) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    category_id INTEGER NOT NULL,
    city_id INTEGER NOT NULL,
    latitude DECIMAL(9, 6) NOT NULL,
    longitude DECIMAL(9, 6) NOT NULL,
    address TEXT NOT NULL,
    phone VARCHAR(30),
    website VARCHAR(255),
    price_level INTEGER,
    avg_rating DECIMAL(3, 2) NOT NULL DEFAULT 0.00,
    review_count INTEGER NOT NULL DEFAULT 0,
    is_permanently_closed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_places_category FOREIGN KEY (category_id) 
        REFERENCES place_categories(category_id) ON DELETE RESTRICT,
    CONSTRAINT fk_places_city FOREIGN KEY (city_id) 
        REFERENCES cities(city_id) ON DELETE RESTRICT,
    CONSTRAINT chk_places_lat CHECK (latitude BETWEEN -90.0 AND 90.0),
    CONSTRAINT chk_places_lng CHECK (longitude BETWEEN -180.0 AND 180.0),
    CONSTRAINT chk_places_price_level CHECK (price_level IS NULL OR price_level BETWEEN 1 AND 4),
    CONSTRAINT chk_places_avg_rating CHECK (avg_rating BETWEEN 0.00 AND 5.00),
    CONSTRAINT chk_places_review_count CHECK (review_count >= 0)
);

-- ---------------------------------------------------------------------
-- 5. Table: opening_hours
-- Operating schedules per place and day of week.
-- Supports midnight crossovers (closes < opens for overnight venues).
-- ---------------------------------------------------------------------
CREATE TABLE opening_hours (
    place_id INTEGER NOT NULL,
    weekday INTEGER NOT NULL,
    opens TIME NOT NULL,
    closes TIME NOT NULL,
    PRIMARY KEY (place_id, weekday),
    CONSTRAINT fk_opening_hours_place FOREIGN KEY (place_id) 
        REFERENCES places(place_id) ON DELETE CASCADE,
    CONSTRAINT chk_opening_hours_weekday CHECK (weekday BETWEEN 1 AND 7)
);

-- ---------------------------------------------------------------------
-- 6. Table: place_reviews
-- User-submitted ratings, textual reviews, and photo uploads for POIs.
-- ---------------------------------------------------------------------
CREATE TABLE place_reviews (
    review_id INTEGER PRIMARY KEY,
    place_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    rating INTEGER NOT NULL,
    review_text TEXT,
    photo_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_reviews_place FOREIGN KEY (place_id) 
        REFERENCES places(place_id) ON DELETE CASCADE,
    CONSTRAINT fk_reviews_user FOREIGN KEY (user_id) 
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT uq_user_place_review UNIQUE (place_id, user_id),
    CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT chk_reviews_photos CHECK (photo_count >= 0)
);

-- ---------------------------------------------------------------------
-- 7. Table: saved_places
-- Curated personal bookmark lists (Favorites, Want to go, Starred, etc.)
-- ---------------------------------------------------------------------
CREATE TABLE saved_places (
    user_id INTEGER NOT NULL,
    place_id INTEGER NOT NULL,
    list_name VARCHAR(100) NOT NULL,
    saved_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (user_id, place_id, list_name),
    CONSTRAINT fk_saved_user FOREIGN KEY (user_id) 
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_saved_place FOREIGN KEY (place_id) 
        REFERENCES places(place_id) ON DELETE CASCADE,
    CONSTRAINT chk_saved_list_name CHECK (
        list_name IN ('Want to go', 'Starred', 'Favourites', 'Travel plans')
    )
);

-- ---------------------------------------------------------------------
-- 8. Table: road_segments
-- Street and highway network segments with geometries and speed limits.
-- ---------------------------------------------------------------------
CREATE TABLE road_segments (
    segment_id INTEGER PRIMARY KEY,
    road_name VARCHAR(200) NOT NULL,
    city_id INTEGER NOT NULL,
    road_type VARCHAR(50) NOT NULL,
    start_lat DECIMAL(9, 6) NOT NULL,
    start_lng DECIMAL(9, 6) NOT NULL,
    end_lat DECIMAL(9, 6) NOT NULL,
    end_lng DECIMAL(9, 6) NOT NULL,
    length_m INTEGER NOT NULL,
    speed_limit_kmph INTEGER NOT NULL,
    CONSTRAINT fk_road_city FOREIGN KEY (city_id) 
        REFERENCES cities(city_id) ON DELETE RESTRICT,
    CONSTRAINT chk_road_type CHECK (road_type IN ('ARTERIAL', 'LOCAL', 'HIGHWAY')),
    CONSTRAINT chk_road_length CHECK (length_m > 0),
    CONSTRAINT chk_road_speed_limit CHECK (speed_limit_kmph > 0),
    CONSTRAINT chk_road_start_lat CHECK (start_lat BETWEEN -90.0 AND 90.0),
    CONSTRAINT chk_road_start_lng CHECK (start_lng BETWEEN -180.0 AND 180.0),
    CONSTRAINT chk_road_end_lat CHECK (end_lat BETWEEN -90.0 AND 90.0),
    CONSTRAINT chk_road_end_lng CHECK (end_lng BETWEEN -180.0 AND 180.0)
);

-- ---------------------------------------------------------------------
-- 9. Table: traffic_readings
-- Time-series telemetry logging vehicular speed and congestion states.
-- ---------------------------------------------------------------------
CREATE TABLE traffic_readings (
    reading_id INTEGER PRIMARY KEY,
    segment_id INTEGER NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL,
    avg_speed_kmph DECIMAL(6, 2) NOT NULL,
    congestion_level VARCHAR(30) NOT NULL,
    CONSTRAINT fk_traffic_segment FOREIGN KEY (segment_id) 
        REFERENCES road_segments(segment_id) ON DELETE CASCADE,
    CONSTRAINT uq_segment_recorded_at UNIQUE (segment_id, recorded_at),
    CONSTRAINT chk_traffic_speed CHECK (avg_speed_kmph >= 0.0),
    CONSTRAINT chk_traffic_congestion CHECK (
        congestion_level IN ('LOW', 'MODERATE', 'HEAVY', 'STANDSTILL')
    )
);

-- ---------------------------------------------------------------------
-- 10. Table: navigation_sessions
-- Live and completed trip navigations with ETA and rerouting metrics.
-- ---------------------------------------------------------------------
CREATE TABLE navigation_sessions (
    session_id INTEGER PRIMARY KEY,
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
    CONSTRAINT fk_nav_user FOREIGN KEY (user_id) 
        REFERENCES users(user_id) ON DELETE SET NULL,
    CONSTRAINT fk_nav_origin_place FOREIGN KEY (origin_place_id) 
        REFERENCES places(place_id) ON DELETE SET NULL,
    CONSTRAINT fk_nav_dest_place FOREIGN KEY (dest_place_id) 
        REFERENCES places(place_id) ON DELETE RESTRICT,
    CONSTRAINT chk_nav_origin_lat CHECK (origin_lat BETWEEN -90.0 AND 90.0),
    CONSTRAINT chk_nav_origin_lng CHECK (origin_lng BETWEEN -180.0 AND 180.0),
    CONSTRAINT chk_nav_travel_mode CHECK (
        travel_mode IN ('DRIVE', 'TRANSIT', 'WALK', 'TWO_WHEELER')
    ),
    CONSTRAINT chk_nav_status CHECK (status IN ('COMPLETED', 'CANCELLED')),
    CONSTRAINT chk_nav_metrics CHECK (
        distance_km >= 0.0 AND eta_minutes > 0 AND rerouted_count >= 0
    ),
    CONSTRAINT chk_nav_actual_minutes CHECK (
        (status = 'COMPLETED' AND actual_minutes IS NOT NULL AND actual_minutes > 0) OR
        (status = 'CANCELLED' AND actual_minutes IS NULL)
    )
);

-- ---------------------------------------------------------------------
-- 11. Table: incident_reports
-- Crowdsourced and agency hazard reports (accidents, waterlogging, police).
-- ---------------------------------------------------------------------
CREATE TABLE incident_reports (
    report_id INTEGER PRIMARY KEY,
    segment_id INTEGER NOT NULL,
    user_id INTEGER,
    incident_type VARCHAR(50) NOT NULL,
    reported_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    upvotes INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT fk_incident_segment FOREIGN KEY (segment_id) 
        REFERENCES road_segments(segment_id) ON DELETE CASCADE,
    CONSTRAINT fk_incident_user FOREIGN KEY (user_id) 
        REFERENCES users(user_id) ON DELETE SET NULL,
    CONSTRAINT chk_incident_type CHECK (
        incident_type IN ('ROADWORK', 'POLICE', 'CLOSURE', 'WATERLOGGING', 'ACCIDENT', 'BREAKDOWN', 'HAZARD')
    ),
    CONSTRAINT chk_incident_expiry CHECK (expires_at > reported_at),
    CONSTRAINT chk_incident_upvotes CHECK (upvotes >= 0)
);
