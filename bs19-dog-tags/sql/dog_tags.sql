-- =============================================================================
-- BS19 - Survivor Dog Tags (Developed by Trident40)
-- Native MariaDB / MySQL tables (also auto-created on resource start)
-- Compatible with Arcainex/bs19 + oxmysql
-- =============================================================================

CREATE TABLE IF NOT EXISTS bs_dog_tags (
    id INT AUTO_INCREMENT PRIMARY KEY,
    tag_uid VARCHAR(24) NOT NULL UNIQUE,
    victim_char_id INT NOT NULL,
    victim_name VARCHAR(80) NOT NULL,
    victim_faction VARCHAR(80) DEFAULT 'Lone Wolf',
    killer_char_id INT NOT NULL,
    killer_name VARCHAR(80) NOT NULL,
    owner_char_id INT DEFAULT NULL,
    tier VARCHAR(16) NOT NULL DEFAULT 'BRONZE',
    streak_minutes INT NOT NULL DEFAULT 0,
    killstreak INT NOT NULL DEFAULT 0,
    is_nemesis TINYINT(1) NOT NULL DEFAULT 0,
    bounty_value INT NOT NULL DEFAULT 500,
    status VARCHAR(16) NOT NULL DEFAULT 'CARRIED',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cashed_at TIMESTAMP NULL DEFAULT NULL,
    INDEX idx_owner_status (owner_char_id, status),
    INDEX idx_killer_victim (killer_char_id, victim_char_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS bs_dog_tag_streaks (
    char_id INT NOT NULL PRIMARY KEY,
    char_name VARCHAR(80) NOT NULL,
    alive_since BIGINT NOT NULL,
    killstreak INT NOT NULL DEFAULT 0,
    best_streak_minutes INT NOT NULL DEFAULT 0,
    tags_collected INT NOT NULL DEFAULT 0,
    tags_cashed INT NOT NULL DEFAULT 0,
    total_earned INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS bs_dog_tag_nemesis (
    killer_char_id INT NOT NULL,
    victim_char_id INT NOT NULL,
    kills INT NOT NULL DEFAULT 1,
    last_kill_at BIGINT NOT NULL,
    PRIMARY KEY (killer_char_id, victim_char_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
