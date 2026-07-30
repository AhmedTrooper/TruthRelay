use sqlx::SqlitePool;

const SCHEMA_SQL: &str = include_str!("migrate.sql");

pub async fn init(pool: &SqlitePool) -> Result<(), sqlx::Error> {
    // Apply the schema. Splitting on `;` is fine because none of our statements
    // contain a `;` inside a string literal.
    for stmt in SCHEMA_SQL.split(';') {
        let trimmed = stmt.trim();
        if trimmed.is_empty() {
            continue;
        }
        sqlx::query(trimmed).execute(pool).await?;
    }
    Ok(())
}
