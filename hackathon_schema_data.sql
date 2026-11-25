-- =====================================================================
--  ONLINE COMPETITION AND HACKATHON MANAGEMENT SYSTEM  (DBMS Capstone #40)
--  File 1 of 2 : schema + sample data + triggers + procedures + views
--  Tested on   : MySQL 9.7 (works on MySQL 8.0+ / MySQL Workbench)
--  How to run  : mysql -u root -p < hackathon_schema_data.sql
-- =====================================================================
DROP DATABASE IF EXISTS hackathon_db;
CREATE DATABASE hackathon_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE hackathon_db;

-- ---------------------------------------------------------------------
-- 1. TABLES (DDL)  -  all in 3NF, every rule enforced by the database
-- ---------------------------------------------------------------------
CREATE TABLE event (
  event_id              INT AUTO_INCREMENT PRIMARY KEY,
  event_name            VARCHAR(100) NOT NULL UNIQUE,
  organizer             VARCHAR(100) NOT NULL,
  mode                  ENUM('Online','Offline','Hybrid') NOT NULL DEFAULT 'Online',
  registration_deadline DATE NOT NULL,
  start_date            DATE NOT NULL,
  end_date              DATE NOT NULL,
  min_team_size         TINYINT NOT NULL DEFAULT 1,
  max_team_size         TINYINT NOT NULL DEFAULT 4,
  CONSTRAINT ck_event_dates CHECK (registration_deadline <= start_date AND start_date <= end_date),
  CONSTRAINT ck_event_team  CHECK (min_team_size >= 1 AND min_team_size <= max_team_size)
);

CREATE TABLE participant (
  participant_id INT AUTO_INCREMENT PRIMARY KEY,
  full_name      VARCHAR(80)  NOT NULL,
  email          VARCHAR(100) NOT NULL UNIQUE,
  phone          CHAR(10)     NOT NULL UNIQUE,
  college        VARCHAR(100) NOT NULL,
  city           VARCHAR(50)  NOT NULL,
  CONSTRAINT ck_part_email CHECK (email LIKE '%_@_%._%'),
  CONSTRAINT ck_part_phone CHECK (phone REGEXP '^[0-9]{10}$')
);

CREATE TABLE registration (
  event_id       INT NOT NULL,
  participant_id INT NOT NULL,
  registered_on  DATE NOT NULL,
  status         ENUM('Registered','Cancelled') NOT NULL DEFAULT 'Registered',
  PRIMARY KEY (event_id, participant_id),
  FOREIGN KEY (event_id)       REFERENCES event(event_id)             ON DELETE CASCADE,
  FOREIGN KEY (participant_id) REFERENCES participant(participant_id) ON DELETE CASCADE
);

CREATE TABLE team (
  team_id    INT AUTO_INCREMENT PRIMARY KEY,
  event_id   INT NOT NULL,
  team_name  VARCHAR(60) NOT NULL,
  leader_id  INT NOT NULL,
  created_on DATE NOT NULL,
  UNIQUE (event_id, team_name),
  UNIQUE (team_id, event_id),                       -- target for composite foreign keys
  FOREIGN KEY (event_id, leader_id) REFERENCES registration(event_id, participant_id)
);

CREATE TABLE team_member (
  team_id        INT NOT NULL,
  event_id       INT NOT NULL,
  participant_id INT NOT NULL,
  joined_on      DATE NOT NULL,
  PRIMARY KEY (team_id, participant_id),
  UNIQUE (event_id, participant_id),                -- one team per participant per event
  FOREIGN KEY (team_id, event_id)        REFERENCES team(team_id, event_id) ON DELETE CASCADE,
  FOREIGN KEY (event_id, participant_id) REFERENCES registration(event_id, participant_id)
);

CREATE TABLE problem_statement (
  ps_id       INT AUTO_INCREMENT PRIMARY KEY,
  event_id    INT NOT NULL,
  title       VARCHAR(120) NOT NULL,
  domain      ENUM('AI/ML','Web','Mobile','IoT','Cybersecurity','HealthTech','FinTech') NOT NULL,
  difficulty  ENUM('Easy','Medium','Hard') NOT NULL,
  description TEXT,
  UNIQUE (event_id, title),
  UNIQUE (ps_id, event_id),
  FOREIGN KEY (event_id) REFERENCES event(event_id) ON DELETE CASCADE
);

CREATE TABLE submission (
  submission_id INT AUTO_INCREMENT PRIMARY KEY,
  team_id       INT NOT NULL UNIQUE,                -- one final submission per team
  event_id      INT NOT NULL,
  ps_id         INT NOT NULL,
  repo_url      VARCHAR(200) NOT NULL,
  demo_url      VARCHAR(200),
  submitted_at  DATETIME NOT NULL,
  UNIQUE (submission_id, event_id),
  FOREIGN KEY (team_id, event_id) REFERENCES team(team_id, event_id),
  FOREIGN KEY (ps_id,  event_id) REFERENCES problem_statement(ps_id, event_id)
);

CREATE TABLE judge (
  judge_id     INT AUTO_INCREMENT PRIMARY KEY,
  full_name    VARCHAR(80)  NOT NULL,
  email        VARCHAR(100) NOT NULL UNIQUE,
  expertise    VARCHAR(80)  NOT NULL,
  organization VARCHAR(100) NOT NULL
);

CREATE TABLE event_judge (
  event_id INT NOT NULL,
  judge_id INT NOT NULL,
  PRIMARY KEY (event_id, judge_id),
  FOREIGN KEY (event_id) REFERENCES event(event_id) ON DELETE CASCADE,
  FOREIGN KEY (judge_id) REFERENCES judge(judge_id) ON DELETE CASCADE
);

CREATE TABLE criteria (
  criteria_id    INT AUTO_INCREMENT PRIMARY KEY,
  event_id       INT NOT NULL,
  criteria_name  VARCHAR(60) NOT NULL,
  max_score      DECIMAL(4,1) NOT NULL DEFAULT 10,
  weight_percent TINYINT NOT NULL,
  UNIQUE (event_id, criteria_name),
  UNIQUE (criteria_id, event_id),
  CONSTRAINT ck_crit_weight CHECK (weight_percent BETWEEN 1 AND 100),
  CONSTRAINT ck_crit_max    CHECK (max_score > 0),
  FOREIGN KEY (event_id) REFERENCES event(event_id) ON DELETE CASCADE
);

CREATE TABLE score (
  score_id      INT AUTO_INCREMENT PRIMARY KEY,
  submission_id INT NOT NULL,
  event_id      INT NOT NULL,
  judge_id      INT NOT NULL,
  criteria_id   INT NOT NULL,
  score_value   DECIMAL(4,1) NOT NULL,
  scored_at     DATETIME NOT NULL,
  UNIQUE (submission_id, judge_id, criteria_id),    -- a judge scores a criterion once
  CONSTRAINT ck_score_nonneg CHECK (score_value >= 0),
  FOREIGN KEY (submission_id, event_id) REFERENCES submission(submission_id, event_id),
  FOREIGN KEY (event_id, judge_id)      REFERENCES event_judge(event_id, judge_id),
  FOREIGN KEY (criteria_id, event_id)   REFERENCES criteria(criteria_id, event_id)
);

CREATE TABLE result (
  event_id      INT NOT NULL,
  submission_id INT NOT NULL,
  total_score   DECIMAL(5,2) NOT NULL,
  rank_position INT NOT NULL,
  computed_at   DATETIME NOT NULL,
  PRIMARY KEY (event_id, submission_id),
  FOREIGN KEY (submission_id, event_id) REFERENCES submission(submission_id, event_id) ON DELETE CASCADE
);

CREATE TABLE score_audit (
  audit_id   INT AUTO_INCREMENT PRIMARY KEY,
  score_id   INT NOT NULL,
  old_value  DECIMAL(4,1) NOT NULL,
  new_value  DECIMAL(4,1) NOT NULL,
  changed_at DATETIME NOT NULL
);

CREATE INDEX idx_participant_college ON participant(college);
CREATE INDEX idx_submission_time     ON submission(submitted_at);

-- ---------------------------------------------------------------------
-- 2. TRIGGERS  (business rules a CHECK cannot express)
-- ---------------------------------------------------------------------
DELIMITER $$

CREATE TRIGGER trg_registration_deadline BEFORE INSERT ON registration
FOR EACH ROW
BEGIN
  IF NEW.registered_on > (SELECT registration_deadline FROM event WHERE event_id = NEW.event_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Registration closed: deadline for this event has passed';
  END IF;
END$$

CREATE TRIGGER trg_team_size BEFORE INSERT ON team_member
FOR EACH ROW
BEGIN
  IF (SELECT COUNT(*) FROM team_member WHERE team_id = NEW.team_id)
       >= (SELECT max_team_size FROM event WHERE event_id = NEW.event_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Team is full: maximum team size for this event reached';
  END IF;
END$$

CREATE TRIGGER trg_submission_window BEFORE INSERT ON submission
FOR EACH ROW
BEGIN
  DECLARE s DATE; DECLARE e DATE;
  SELECT start_date, end_date INTO s, e FROM event WHERE event_id = NEW.event_id;
  IF NEW.submitted_at < s OR NEW.submitted_at >= DATE_ADD(e, INTERVAL 1 DAY) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Submission rejected: outside the event start/end window';
  END IF;
END$$

CREATE TRIGGER trg_score_range_ins BEFORE INSERT ON score
FOR EACH ROW
BEGIN
  IF NEW.score_value > (SELECT max_score FROM criteria WHERE criteria_id = NEW.criteria_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Score is higher than the maximum allowed for this criterion';
  END IF;
END$$

CREATE TRIGGER trg_score_range_upd BEFORE UPDATE ON score
FOR EACH ROW
BEGIN
  IF NEW.score_value > (SELECT max_score FROM criteria WHERE criteria_id = NEW.criteria_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Score is higher than the maximum allowed for this criterion';
  END IF;
END$$

CREATE TRIGGER trg_score_audit AFTER UPDATE ON score
FOR EACH ROW
BEGIN
  IF OLD.score_value <> NEW.score_value THEN
    INSERT INTO score_audit(score_id, old_value, new_value, changed_at)
    VALUES (OLD.score_id, OLD.score_value, NEW.score_value, NOW());
  END IF;
END$$

-- ---------------------------------------------------------------------
-- 3. STORED FUNCTION + PROCEDURES
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_team_size(p_team_id INT) RETURNS INT
DETERMINISTIC READS SQL DATA
BEGIN
  RETURN (SELECT COUNT(*) FROM team_member WHERE team_id = p_team_id);
END$$

-- Create a team and add its leader as first member, all-or-nothing (transaction)
CREATE PROCEDURE sp_create_team(IN p_event_id INT, IN p_team_name VARCHAR(60),
                                IN p_leader_id INT, IN p_date DATE, OUT p_team_id INT)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;
  START TRANSACTION;
    INSERT INTO team(event_id, team_name, leader_id, created_on)
    VALUES (p_event_id, p_team_name, p_leader_id, p_date);
    SET p_team_id = LAST_INSERT_ID();
    INSERT INTO team_member(team_id, event_id, participant_id, joined_on)
    VALUES (p_team_id, p_event_id, p_leader_id, p_date);
  COMMIT;
END$$

-- Final score = sum over criteria of ( average judge score / max_score * weight% )  -> out of 100
-- RANK() gives equal rank to equal totals (ties)
CREATE PROCEDURE sp_compute_rankings(IN p_event_id INT)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;
  START TRANSACTION;
    DELETE FROM result WHERE event_id = p_event_id;
    INSERT INTO result (event_id, submission_id, total_score, rank_position, computed_at)
    WITH per_criterion AS (
      SELECT s.submission_id, s.criteria_id, AVG(s.score_value) AS avg_score
      FROM score s WHERE s.event_id = p_event_id
      GROUP BY s.submission_id, s.criteria_id
    ), totals AS (
      SELECT pc.submission_id,
             ROUND(SUM(pc.avg_score / c.max_score * c.weight_percent), 2) AS total_score
      FROM per_criterion pc JOIN criteria c ON c.criteria_id = pc.criteria_id
      GROUP BY pc.submission_id
    )
    SELECT p_event_id, submission_id, total_score,
           RANK() OVER (ORDER BY total_score DESC), NOW()
    FROM totals;
  COMMIT;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- 4. VIEWS
-- ---------------------------------------------------------------------
CREATE VIEW v_event_summary AS
SELECT e.event_id, e.event_name, e.mode,
       (SELECT COUNT(*) FROM registration r WHERE r.event_id = e.event_id AND r.status='Registered') AS participants,
       (SELECT COUNT(*) FROM team t WHERE t.event_id = e.event_id)       AS teams,
       (SELECT COUNT(*) FROM submission s WHERE s.event_id = e.event_id) AS submissions
FROM event e;

CREATE VIEW v_team_roster AS
SELECT e.event_name, t.team_id, t.team_name, p.full_name AS member,
       IF(p.participant_id = t.leader_id, 'Leader', 'Member') AS role, p.college
FROM team_member tm
JOIN team t        ON t.team_id = tm.team_id
JOIN event e       ON e.event_id = t.event_id
JOIN participant p ON p.participant_id = tm.participant_id;

CREATE VIEW v_score_sheet AS
SELECT e.event_name, t.team_name, j.full_name AS judge, c.criteria_name, s.score_value, c.max_score
FROM score s
JOIN submission sb ON sb.submission_id = s.submission_id
JOIN team t        ON t.team_id = sb.team_id
JOIN event e       ON e.event_id = s.event_id
JOIN judge j       ON j.judge_id = s.judge_id
JOIN criteria c    ON c.criteria_id = s.criteria_id;

CREATE VIEW v_leaderboard AS
SELECT e.event_name, r.rank_position AS `rank`, t.team_name, ps.title AS problem_statement, r.total_score
FROM result r
JOIN event e              ON e.event_id = r.event_id
JOIN submission sb        ON sb.submission_id = r.submission_id
JOIN team t               ON t.team_id = sb.team_id
JOIN problem_statement ps ON ps.ps_id = sb.ps_id
ORDER BY r.event_id, r.rank_position, t.team_name;

-- ---------------------------------------------------------------------
-- 5. ROLES (DCL)
-- ---------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS 'hk_admin', 'hk_judge', 'hk_participant';
GRANT ALL PRIVILEGES ON hackathon_db.* TO 'hk_admin';
GRANT SELECT ON hackathon_db.v_score_sheet TO 'hk_judge';
GRANT SELECT, INSERT, UPDATE ON hackathon_db.score TO 'hk_judge';
GRANT SELECT ON hackathon_db.v_leaderboard TO 'hk_participant';
GRANT SELECT ON hackathon_db.v_team_roster TO 'hk_participant';

-- ---------------------------------------------------------------------
-- 6. SAMPLE DATA (DML)
-- ---------------------------------------------------------------------
INSERT INTO event (event_name, organizer, mode, registration_deadline, start_date, end_date, min_team_size, max_team_size) VALUES
 ('CodeSprint 2026',   'Department of Computer Science', 'Hybrid', '2026-10-05', '2026-10-10', '2026-10-12', 2, 4),
 ('AI Innovate 2027',  'Department of Computer Science', 'Online', '2027-02-10', '2027-02-20', '2027-02-22', 1, 3);

INSERT INTO participant (full_name, email, phone, college, city) VALUES
 ('Aarav Sharma',   'aarav.sharma@example.com',   '9810000001', 'Delhi Technical University', 'Delhi'),
 ('Diya Verma',     'diya.verma@example.com',     '9810000002', 'Delhi Technical University', 'Delhi'),
 ('Rohan Gupta',    'rohan.gupta@example.com',    '9810000003', 'Delhi Technical University', 'Delhi'),
 ('Ananya Singh',   'ananya.singh@example.com',   '9810000004', 'IIIT Allahabad',             'Prayagraj'),
 ('Kabir Mehta',    'kabir.mehta@example.com',    '9810000005', 'IIIT Allahabad',             'Prayagraj'),
 ('Ishita Jain',    'ishita.jain@example.com',    '9810000006', 'VIT Vellore',                'Vellore'),
 ('Vivaan Reddy',   'vivaan.reddy@example.com',   '9810000007', 'VIT Vellore',                'Vellore'),
 ('Saanvi Nair',    'saanvi.nair@example.com',    '9810000008', 'NIT Calicut',                'Kozhikode'),
 ('Arjun Patel',    'arjun.patel@example.com',    '9810000009', 'NIT Calicut',                'Kozhikode'),
 ('Meera Iyer',     'meera.iyer@example.com',     '9810000010', 'NIT Calicut',                'Kozhikode'),
 ('Aditya Rao',     'aditya.rao@example.com',     '9810000011', 'BITS Pilani',                'Pilani'),
 ('Navya Kapoor',   'navya.kapoor@example.com',   '9810000012', 'BITS Pilani',                'Pilani'),
 ('Krish Malhotra', 'krish.malhotra@example.com', '9810000013', 'BITS Pilani',                'Pilani'),
 ('Riya Chauhan',   'riya.chauhan@example.com',   '9810000014', 'Jadavpur University',        'Kolkata'),
 ('Dev Banerjee',   'dev.banerjee@example.com',   '9810000015', 'Jadavpur University',        'Kolkata'),
 ('Tanvi Desai',    'tanvi.desai@example.com',    '9810000016', 'Jadavpur University',        'Kolkata'),
 ('Yash Agarwal',   'yash.agarwal@example.com',   '9810000017', 'Delhi Technical University', 'Delhi'),
 ('Pooja Bhatt',    'pooja.bhatt@example.com',    '9810000018', 'IIIT Allahabad',             'Prayagraj'),
 ('Harsh Tiwari',   'harsh.tiwari@example.com',   '9810000019', 'VIT Vellore',                'Vellore'),
 ('Nisha Kulkarni', 'nisha.kulkarni@example.com', '9810000020', 'NIT Calicut',                'Kozhikode'),
 ('Manav Joshi',    'manav.joshi@example.com',    '9810000021', 'BITS Pilani',                'Pilani'),
 ('Sneha Pillai',   'sneha.pillai@example.com',   '9810000022', 'VIT Vellore',                'Vellore');

-- CodeSprint 2026: participants 1-20 registered before the 2026-10-05 deadline
INSERT INTO registration (event_id, participant_id, registered_on)
SELECT 1, participant_id, DATE_ADD('2026-09-20', INTERVAL (participant_id MOD 10) DAY)
FROM participant WHERE participant_id <= 20;
-- AI Innovate 2027: registrations just opened
INSERT INTO registration (event_id, participant_id, registered_on) VALUES
 (2,1,'2026-11-01'),(2,4,'2026-11-02'),(2,8,'2026-11-03'),(2,11,'2026-11-03'),(2,14,'2026-11-05'),(2,21,'2026-11-06');

INSERT INTO judge (full_name, email, expertise, organization) VALUES
 ('Dr. Neha Kulshreshtha', 'neha.k@example.org',  'Machine Learning',  'IIT Delhi'),
 ('Mr. Sandeep Rawat',     'sandeep.r@example.org','Cloud and DevOps', 'Infosys'),
 ('Ms. Farah Khan',        'farah.k@example.org',  'Product Design',   'Microsoft'),
 ('Dr. Prakash Menon',     'prakash.m@example.org','Cybersecurity',    'C-DAC');
INSERT INTO event_judge VALUES (1,1),(1,2),(1,3),(2,1),(2,4);

INSERT INTO criteria (event_id, criteria_name, max_score, weight_percent) VALUES
 (1,'Innovation',10,30),(1,'Technical Complexity',10,30),(1,'Impact',10,25),(1,'Presentation',10,15);
INSERT INTO criteria (event_id, criteria_name, max_score, weight_percent)
SELECT 2, criteria_name, max_score, weight_percent FROM criteria WHERE event_id = 1;

INSERT INTO problem_statement (event_id, title, domain, difficulty, description) VALUES
 (1,'Smart Crop Disease Detector',    'AI/ML',         'Hard',   'Detect crop leaf diseases from phone photos.'),
 (1,'Campus Carpool Planner',         'Mobile',        'Medium', 'Match students travelling the same route.'),
 (1,'Phishing Link Shield',           'Cybersecurity', 'Medium', 'Browser extension that flags phishing URLs.'),
 (1,'Rural Telehealth Connect',       'HealthTech',    'Hard',   'Low-bandwidth video consultation platform.'),
 (1,'Expense Splitter with UPI',      'FinTech',       'Easy',   'Split group expenses and settle through UPI.'),
 (2,'LLM Study Buddy',                'AI/ML',         'Medium', 'Course-aware question answering assistant.');

-- Teams of CodeSprint 2026 (created through members' registrations)
INSERT INTO team (event_id, team_name, leader_id, created_on) VALUES
 (1,'Neural Ninjas',  1, '2026-10-01'),
 (1,'Byte Builders',  5, '2026-10-01'),
 (1,'Code Crusaders', 8, '2026-10-02'),
 (1,'Data Dynamos',  11, '2026-10-02'),
 (1,'Pixel Pioneers',14, '2026-10-03'),
 (1,'Secure Squad',  17, '2026-10-03');

INSERT INTO team_member (team_id, event_id, participant_id, joined_on) VALUES
 (1,1,1,'2026-10-01'),(1,1,2,'2026-10-01'),(1,1,3,'2026-10-01'),(1,1,4,'2026-10-01'),
 (2,1,5,'2026-10-01'),(2,1,6,'2026-10-01'),(2,1,7,'2026-10-02'),
 (3,1,8,'2026-10-02'),(3,1,9,'2026-10-02'),(3,1,10,'2026-10-02'),
 (4,1,11,'2026-10-02'),(4,1,12,'2026-10-03'),(4,1,13,'2026-10-03'),
 (5,1,14,'2026-10-03'),(5,1,15,'2026-10-03'),(5,1,16,'2026-10-03'),
 (6,1,17,'2026-10-03'),(6,1,18,'2026-10-04');

-- 5 of the 6 teams submitted ("Secure Squad" did not)
INSERT INTO submission (team_id, event_id, ps_id, repo_url, demo_url, submitted_at) VALUES
 (1,1,1,'https://github.com/neural-ninjas/crop-doctor','https://youtu.be/demo-ninjas','2026-10-12 09:40:00'),
 (2,1,2,'https://github.com/byte-builders/carpool',    NULL,                          '2026-10-12 10:15:00'),
 (3,1,1,'https://github.com/code-crusaders/leafscan',  'https://youtu.be/demo-crusaders','2026-10-12 11:05:00'),
 (4,1,4,'https://github.com/data-dynamos/telehealth',  'https://youtu.be/demo-dynamos','2026-10-12 11:30:00'),
 (5,1,3,'https://github.com/pixel-pioneers/phishshield', NULL,                        '2026-10-12 12:00:00');

-- 5 submissions x 3 judges x 4 criteria = 60 score rows
INSERT INTO score (submission_id, event_id, judge_id, criteria_id, score_value, scored_at) VALUES
  (1,1,1,1,9,'2026-10-13 11:10:00'),
  (1,1,1,2,8,'2026-10-13 11:20:00'),
  (1,1,1,3,9,'2026-10-13 11:30:00'),
  (1,1,1,4,8,'2026-10-13 11:40:00'),
  (1,1,2,1,8,'2026-10-13 12:10:00'),
  (1,1,2,2,9,'2026-10-13 12:20:00'),
  (1,1,2,3,9,'2026-10-13 12:30:00'),
  (1,1,2,4,9,'2026-10-13 12:40:00'),
  (1,1,3,1,9,'2026-10-13 13:10:00'),
  (1,1,3,2,9,'2026-10-13 13:20:00'),
  (1,1,3,3,8,'2026-10-13 13:30:00'),
  (1,1,3,4,8,'2026-10-13 13:40:00'),
  (2,1,1,1,7,'2026-10-13 11:10:00'),
  (2,1,1,2,6,'2026-10-13 11:20:00'),
  (2,1,1,3,8,'2026-10-13 11:30:00'),
  (2,1,1,4,9,'2026-10-13 11:40:00'),
  (2,1,2,1,8,'2026-10-13 12:10:00'),
  (2,1,2,2,7,'2026-10-13 12:20:00'),
  (2,1,2,3,7,'2026-10-13 12:30:00'),
  (2,1,2,4,8,'2026-10-13 12:40:00'),
  (2,1,3,1,7,'2026-10-13 13:10:00'),
  (2,1,3,2,7,'2026-10-13 13:20:00'),
  (2,1,3,3,8,'2026-10-13 13:30:00'),
  (2,1,3,4,9,'2026-10-13 13:40:00'),
  (3,1,1,1,8,'2026-10-13 11:10:00'),
  (3,1,1,2,8,'2026-10-13 11:20:00'),
  (3,1,1,3,7,'2026-10-13 11:30:00'),
  (3,1,1,4,7,'2026-10-13 11:40:00'),
  (3,1,2,1,7,'2026-10-13 12:10:00'),
  (3,1,2,2,8,'2026-10-13 12:20:00'),
  (3,1,2,3,8,'2026-10-13 12:30:00'),
  (3,1,2,4,8,'2026-10-13 12:40:00'),
  (3,1,3,1,8,'2026-10-13 13:10:00'),
  (3,1,3,2,7,'2026-10-13 13:20:00'),
  (3,1,3,3,7,'2026-10-13 13:30:00'),
  (3,1,3,4,7,'2026-10-13 13:40:00'),
  (4,1,1,1,8,'2026-10-13 11:10:00'),
  (4,1,1,2,8,'2026-10-13 11:20:00'),
  (4,1,1,3,7,'2026-10-13 11:30:00'),
  (4,1,1,4,7,'2026-10-13 11:40:00'),
  (4,1,2,1,7,'2026-10-13 12:10:00'),
  (4,1,2,2,8,'2026-10-13 12:20:00'),
  (4,1,2,3,8,'2026-10-13 12:30:00'),
  (4,1,2,4,8,'2026-10-13 12:40:00'),
  (4,1,3,1,8,'2026-10-13 13:10:00'),
  (4,1,3,2,7,'2026-10-13 13:20:00'),
  (4,1,3,3,7,'2026-10-13 13:30:00'),
  (4,1,3,4,7,'2026-10-13 13:40:00'),
  (5,1,1,1,6,'2026-10-13 11:10:00'),
  (5,1,1,2,5,'2026-10-13 11:20:00'),
  (5,1,1,3,6,'2026-10-13 11:30:00'),
  (5,1,1,4,7,'2026-10-13 11:40:00'),
  (5,1,2,1,5,'2026-10-13 12:10:00'),
  (5,1,2,2,6,'2026-10-13 12:20:00'),
  (5,1,2,3,7,'2026-10-13 12:30:00'),
  (5,1,2,4,6,'2026-10-13 12:40:00'),
  (5,1,3,1,6,'2026-10-13 13:10:00'),
  (5,1,3,2,6,'2026-10-13 13:20:00'),
  (5,1,3,3,5,'2026-10-13 13:30:00'),
  (5,1,3,4,7,'2026-10-13 13:40:00');
