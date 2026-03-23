-- 012_cleanup_old_semesters.sql
-- Remove user_disciplinas links for disciplines from past semesters.
-- Current semester: 2026/1

DELETE FROM user_disciplinas ud
USING disciplinas d
WHERE ud.disciplina_id = d.id
  AND d.semestre IS NOT NULL
  AND d.semestre != '2026/1';
