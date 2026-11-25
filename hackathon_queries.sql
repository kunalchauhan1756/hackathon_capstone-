-- =====================================================================
--  File 2 of 2 : queries, transaction demo and constraint tests
--  Run AFTER hackathon_schema_data.sql   (mysql -u root -p < hackathon_queries.sql)
--  Q9 and Q16 write data: to run this file again, reload hackathon_schema_data.sql first.
--  Part A (Q1-Q16) runs top to bottom. Part B (T1-T8) is meant to FAIL: run each
--  statement one by one in Workbench and read the error message.
-- =====================================================================
USE hackathon_db;

-- Q1. Event summary (view)
SELECT * FROM v_event_summary;

-- Q2. Team roster of CodeSprint 2026 (view, JOIN)
SELECT team_name, member, role, college
FROM v_team_roster
WHERE event_name = 'CodeSprint 2026'
ORDER BY team_id, role, member;

-- Q3. Team size using the stored function, with free slots
SELECT t.team_name, fn_team_size(t.team_id) AS members, e.max_team_size,
       e.max_team_size - fn_team_size(t.team_id) AS free_slots
FROM team t JOIN event e ON e.event_id = t.event_id
WHERE t.event_id = 1
ORDER BY free_slots DESC, t.team_name;

-- Q4. Registered participants who are not in any team (NOT EXISTS)
SELECT p.participant_id, p.full_name, p.college
FROM registration r
JOIN participant p ON p.participant_id = r.participant_id
WHERE r.event_id = 1
  AND NOT EXISTS (SELECT 1 FROM team_member tm
                  WHERE tm.event_id = r.event_id AND tm.participant_id = r.participant_id);

-- Q5. Teams that have not submitted (LEFT JOIN ... IS NULL)
SELECT t.team_name, t.created_on
FROM team t LEFT JOIN submission s ON s.team_id = t.team_id
WHERE t.event_id = 1 AND s.submission_id IS NULL;

-- Q6. Problem statement popularity, including unused ones (LEFT JOIN, GROUP BY)
SELECT ps.title, ps.domain, ps.difficulty, COUNT(s.submission_id) AS teams_chose
FROM problem_statement ps
LEFT JOIN submission s ON s.ps_id = ps.ps_id
WHERE ps.event_id = 1
GROUP BY ps.ps_id, ps.title, ps.domain, ps.difficulty
ORDER BY teams_chose DESC, ps.title;

-- Q7. Score sheet of one team (view)
SELECT judge, criteria_name, score_value, max_score
FROM v_score_sheet
WHERE team_name = 'Neural Ninjas'
ORDER BY judge, FIELD(criteria_name,'Innovation','Technical Complexity','Impact','Presentation');

-- Q8. Average score per criterion for every team (conditional aggregation)
SELECT team_name,
  ROUND(AVG(CASE WHEN criteria_name='Innovation'           THEN score_value END),2) AS innovation,
  ROUND(AVG(CASE WHEN criteria_name='Technical Complexity' THEN score_value END),2) AS technical,
  ROUND(AVG(CASE WHEN criteria_name='Impact'               THEN score_value END),2) AS impact,
  ROUND(AVG(CASE WHEN criteria_name='Presentation'         THEN score_value END),2) AS presentation
FROM v_score_sheet
WHERE event_name = 'CodeSprint 2026'
GROUP BY team_name
ORDER BY team_name;

-- Q9. Compute rankings (stored procedure) and show the leaderboard (view)
CALL sp_compute_rankings(1);
SELECT * FROM v_leaderboard WHERE event_name = 'CodeSprint 2026';

-- Q10. Winners = rank 1 to 3 (ties share a rank)
SELECT `rank`, team_name, total_score
FROM v_leaderboard
WHERE event_name = 'CodeSprint 2026' AND `rank` <= 3;

-- Q11. RANK vs DENSE_RANK vs ROW_NUMBER (window functions)
SELECT t.team_name, r.total_score,
       RANK()       OVER (ORDER BY r.total_score DESC) AS rank_pos,
       DENSE_RANK() OVER (ORDER BY r.total_score DESC) AS dense_rank_pos,
       ROW_NUMBER() OVER (ORDER BY r.total_score DESC, t.team_name) AS row_no
FROM result r
JOIN submission s ON s.submission_id = r.submission_id
JOIN team t ON t.team_id = s.team_id
WHERE r.event_id = 1;

-- Q12. Teams scoring above the event average (subquery)
SELECT team_name, total_score
FROM v_leaderboard
WHERE event_name = 'CodeSprint 2026'
  AND total_score > (SELECT AVG(total_score) FROM result WHERE event_id = 1);

-- Q13. Judge strictness: average, minimum and maximum score given
SELECT judge, ROUND(AVG(score_value),2) AS avg_given, MIN(score_value) AS lowest, MAX(score_value) AS highest
FROM v_score_sheet
WHERE event_name = 'CodeSprint 2026'
GROUP BY judge
ORDER BY avg_given;

-- Q14. College-wise participation and number of teams (GROUP BY, HAVING)
SELECT p.college,
       COUNT(DISTINCT r.participant_id) AS participants,
       COUNT(DISTINCT tm.team_id)       AS teams_represented
FROM registration r
JOIN participant p ON p.participant_id = r.participant_id
LEFT JOIN team_member tm ON tm.event_id = r.event_id AND tm.participant_id = r.participant_id
WHERE r.event_id = 1
GROUP BY p.college
HAVING participants >= 3
ORDER BY participants DESC, p.college;

-- Q15. Transaction demo: update a score, see the audit log, then ROLLBACK
START TRANSACTION;
UPDATE score SET score_value = 10 WHERE score_id = 1;
SELECT score_id, old_value, new_value FROM score_audit;      -- trigger logged the change
ROLLBACK;
SELECT COUNT(*) AS audit_rows_after_rollback FROM score_audit;
SELECT score_id, score_value FROM score WHERE score_id = 1;  -- original value is back

-- Q16. Create a team with the stored procedure (transaction inside), then add a member
CALL sp_create_team(2, 'Prompt Pilots', 1, '2026-11-10', @new_team);
INSERT INTO team_member (team_id, event_id, participant_id, joined_on) VALUES (@new_team, 2, 4, '2026-11-10');
SELECT team_name, member, role FROM v_team_roster WHERE event_name = 'AI Innovate 2027';

-- ---------------------------------------------------------------------
-- PART B: constraint and trigger tests (every statement below must raise an error)
-- ---------------------------------------------------------------------
-- T1. One team per participant per event (UNIQUE)
INSERT INTO team_member (team_id, event_id, participant_id, joined_on) VALUES (2, 1, 1, '2026-10-04');

-- T2. Registration after the deadline (trigger)
INSERT INTO registration (event_id, participant_id, registered_on) VALUES (1, 21, '2026-10-08');

-- T3. Team already has the maximum of 4 members (trigger)
INSERT INTO team_member (team_id, event_id, participant_id, joined_on) VALUES (1, 1, 19, '2026-10-04');

-- T4. Submission outside the event window (trigger)
INSERT INTO submission (team_id, event_id, ps_id, repo_url, submitted_at) VALUES (6, 1, 5, 'https://github.com/secure-squad/splitter', '2026-10-20 10:00:00');

-- T5. Score above the criterion maximum (trigger)
UPDATE score SET score_value = 11 WHERE score_id = 1;

-- T6. Judge who is not assigned to the event (composite foreign key)
INSERT INTO score (submission_id, event_id, judge_id, criteria_id, score_value, scored_at) VALUES (1, 1, 4, 1, 5, '2026-10-13 10:00:00');

-- T7. Invalid phone number (CHECK)
INSERT INTO participant (full_name, email, phone, college, city) VALUES ('Test User','test.user@example.com','12345','Test College','Delhi');

-- T8. Problem statement from a different event (composite foreign key)
INSERT INTO submission (team_id, event_id, ps_id, repo_url, submitted_at) VALUES (6, 1, 6, 'https://github.com/secure-squad/llm', '2026-10-11 10:00:00');

