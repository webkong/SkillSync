use rusqlite::{params, Connection};

pub struct Database {
    conn: Connection,
}

impl Database {
    pub fn open() -> Result<Self, String> {
        let home = dirs::home_dir().ok_or("Cannot find home directory")?;
        let db_path = home.join(".agent").join("skills.db");

        // Ensure .agent directory exists
        std::fs::create_dir_all(home.join(".agent"))
            .map_err(|e| format!("Failed to create .agent dir: {}", e))?;

        let conn =
            Connection::open(&db_path).map_err(|e| format!("Failed to open database: {}", e))?;

        let db = Self { conn };
        db.init_tables()?;
        Ok(db)
    }

    fn init_tables(&self) -> Result<(), String> {
        self.conn
            .execute_batch(
                "
            CREATE TABLE IF NOT EXISTS skill_metadata (
                id TEXT PRIMARY KEY,
                source_dir TEXT NOT NULL,
                agent_source TEXT NOT NULL DEFAULT '',
                name TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '',
                tags TEXT NOT NULL DEFAULT '[]',
                compatible_agents TEXT NOT NULL DEFAULT '[\"*\"]',
                version TEXT NOT NULL DEFAULT '0.1.0',
                is_organized INTEGER NOT NULL DEFAULT 0,
                linked_agents TEXT NOT NULL DEFAULT '[]',
                updated_at TEXT NOT NULL DEFAULT ''
            );
            CREATE TABLE IF NOT EXISTS app_config (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
        ",
            )
            .map_err(|e| format!("Failed to create tables: {}", e))?;

        // Migration: add linked_agents column if it doesn't exist (for existing databases)
        self.conn
            .execute_batch(
                "ALTER TABLE skill_metadata ADD COLUMN linked_agents TEXT NOT NULL DEFAULT '[]';",
            )
            .ok(); // Ignore error if column already exists

        Ok(())
    }

    pub fn upsert_skills(&self, skills: &[crate::models::SkillEntry]) -> Result<(), String> {
        let mut stmt = self
            .conn
            .prepare(
                "INSERT OR REPLACE INTO skill_metadata (id, source_dir, name, description, tags, compatible_agents, version, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, datetime('now'))",
            )
            .map_err(|e| format!("Failed to prepare upsert: {}", e))?;

        for skill in skills {
            let tags_json = serde_json::to_string(&skill.manifest.tags).unwrap_or_default();
            let agents_json =
                serde_json::to_string(&skill.manifest.compatible_agents).unwrap_or_default();

            stmt.execute(params![
                skill.id,
                skill.source_dir,
                skill.manifest.name,
                skill.manifest.description,
                tags_json,
                agents_json,
                skill.manifest.version,
            ])
            .map_err(|e| format!("Failed to upsert skill {}: {}", skill.id, e))?;
        }
        Ok(())
    }

    pub fn upsert_skill_with_agent(
        &self,
        id: &str,
        source_dir: &str,
        agent_source: &str,
        name: &str,
        description: &str,
        tags: &str,
        compatible_agents: &str,
        version: &str,
        linked_agents: &str,
    ) -> Result<(), String> {
        self.conn
            .execute(
                "INSERT OR REPLACE INTO skill_metadata (id, source_dir, agent_source, name, description, tags, compatible_agents, version, linked_agents, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, datetime('now'))",
                params![
                    id,
                    source_dir,
                    agent_source,
                    name,
                    description,
                    tags,
                    compatible_agents,
                    version,
                    linked_agents,
                ],
            )
            .map_err(|e| format!("Failed to upsert skill {}: {}", id, e))?;
        Ok(())
    }

    pub fn get_all_skills(
        &self,
    ) -> Result<Vec<crate::models::OrganizedSkill>, String> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT id, source_dir, agent_source, name, description, tags, compatible_agents, version, is_organized, linked_agents FROM skill_metadata ORDER BY name",
            )
            .map_err(|e| format!("Failed to prepare query: {}", e))?;

        let rows = stmt
            .query_map([], |row| {
                Ok(crate::models::OrganizedSkill {
                    id: row.get(0)?,
                    source_dir: row.get(1)?,
                    agent_source: row.get(2)?,
                    name: row.get(3)?,
                    description: row.get(4)?,
                    tags: row.get(5)?,
                    compatible_agents: row.get(6)?,
                    version: row.get(7)?,
                    is_organized: row.get::<_, i32>(8)? != 0,
                    linked_agents: row.get(9)?,
                })
            })
            .map_err(|e| format!("Failed to query skills: {}", e))?;

        let mut skills = Vec::new();
        for row in rows {
            skills.push(row.map_err(|e| format!("Failed to read row: {}", e))?);
        }
        Ok(skills)
    }

    pub fn get_unorganized_skills(
        &self,
    ) -> Result<Vec<crate::models::OrganizedSkill>, String> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT id, source_dir, agent_source, name, description, tags, compatible_agents, version, is_organized, linked_agents FROM skill_metadata WHERE is_organized = 0 ORDER BY name",
            )
            .map_err(|e| format!("Failed to prepare query: {}", e))?;

        let rows = stmt
            .query_map([], |row| {
                Ok(crate::models::OrganizedSkill {
                    id: row.get(0)?,
                    source_dir: row.get(1)?,
                    agent_source: row.get(2)?,
                    name: row.get(3)?,
                    description: row.get(4)?,
                    tags: row.get(5)?,
                    compatible_agents: row.get(6)?,
                    version: row.get(7)?,
                    is_organized: false,
                    linked_agents: row.get(9)?,
                })
            })
            .map_err(|e| format!("Failed to query unorganized skills: {}", e))?;

        let mut skills = Vec::new();
        for row in rows {
            skills.push(row.map_err(|e| format!("Failed to read row: {}", e))?);
        }
        Ok(skills)
    }

    pub fn set_organized(&self, skill_id: &str) -> Result<(), String> {
        self.conn
            .execute(
                "UPDATE skill_metadata SET is_organized = 1 WHERE id = ?1",
                params![skill_id],
            )
            .map_err(|e| format!("Failed to mark skill organized: {}", e))?;
        Ok(())
    }

    pub fn has_organized(&self) -> Result<bool, String> {
        let val: String = self
            .conn
            .query_row(
                "SELECT value FROM app_config WHERE key = 'has_organized'",
                [],
                |row| row.get(0),
            )
            .unwrap_or_default();
        Ok(val == "true")
    }

    pub fn set_has_organized(&self) -> Result<(), String> {
        self.conn
            .execute(
                "INSERT OR REPLACE INTO app_config (key, value) VALUES ('has_organized', 'true')",
                [],
            )
            .map_err(|e| format!("Failed to set has_organized: {}", e))?;
        Ok(())
    }

    pub fn clear_all(&self) -> Result<(), String> {
        self.conn
            .execute("DELETE FROM skill_metadata", [])
            .map_err(|e| format!("Failed to clear skills: {}", e))?;
        Ok(())
    }

    /// Update source_dir, is_organized, and linked_agents for a skill (used after restore).
    pub fn update_skill_location(
        &self,
        skill_id: &str,
        new_source_dir: &str,
        new_agent_source: &str,
        is_organized: bool,
        linked_agents: &str,
    ) -> Result<(), String> {
        self.conn
            .execute(
                "UPDATE skill_metadata SET source_dir = ?1, agent_source = ?2, is_organized = ?3, linked_agents = ?4, updated_at = datetime('now') WHERE id = ?5",
                params![new_source_dir, new_agent_source, is_organized as i32, linked_agents, skill_id],
            )
            .map_err(|e| format!("Failed to update skill location: {}", e))?;
        Ok(())
    }
}
