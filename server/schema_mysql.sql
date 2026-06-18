CREATE TABLE IF NOT EXISTS users (
  id CHAR(36) PRIMARY KEY,
  phone VARCHAR(11) UNIQUE NOT NULL,
  nickname VARCHAR(50),
  avatar_url TEXT,
  password_hash VARCHAR(255) NOT NULL,
  privacy_settings JSON,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS friendships (
  id CHAR(36) PRIMARY KEY,
  user_id_1 CHAR(36) NOT NULL,
  user_id_2 CHAR(36) NOT NULL,
  initiator_id CHAR(36) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY unique_pair (user_id_1, user_id_2),
  FOREIGN KEY (user_id_1) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id_2) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (initiator_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS geo_fences (
  id CHAR(36) PRIMARY KEY,
  user_id CHAR(36) NOT NULL,
  name VARCHAR(50) NOT NULL,
  lat DOUBLE NOT NULL,
  lng DOUBLE NOT NULL,
  radius DOUBLE DEFAULT 100,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS fence_events (
  id           CHAR(36) PRIMARY KEY,
  receiver_id  CHAR(36) NOT NULL,
  sender_id    CHAR(36) NOT NULL,
  content      TEXT,
  type         VARCHAR(20) NOT NULL DEFAULT 'fence_auto',
  delivered    TINYINT(1) NOT NULL DEFAULT 0,
  expired      TINYINT(1) NOT NULL DEFAULT 0,
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (receiver_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (sender_id)   REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_fence_events_receiver ON fence_events(receiver_id, delivered, expired);
