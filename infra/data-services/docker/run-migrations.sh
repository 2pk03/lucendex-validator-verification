#!/bin/bash
set -e

echo "Running database migrations..."

# Directory containing migration files
MIGRATIONS_DIR="/docker-entrypoint-initdb.d/migrations"

# Apply each migration in order
for migration in $(ls -1 ${MIGRATIONS_DIR}/*.sql | sort); do
    filename=$(basename "$migration")
    version=$(echo "$filename" | sed 's/^\([0-9]*\)_.*/\1/')
    name=$(echo "$filename" | sed 's/^[0-9]*_\(.*\)\.sql$/\1/')
    
    # Check if migration already applied
    applied=$(psql -U postgres -d lucendex -tAc "SELECT COUNT(*) FROM core.schema_migrations WHERE version = ${version}")
    
    if [ "$applied" = "0" ]; then
        echo "  Applying migration ${version}: ${name}"
        psql -U postgres -d lucendex -f "$migration"
        psql -U postgres -d lucendex -c "INSERT INTO core.schema_migrations (version, name) VALUES (${version}, '${name}')"
        echo "  ✓ Migration ${version} applied"
    else
        echo "  ⊘ Migration ${version} already applied"
    fi
done

echo "✓ All migrations applied"
