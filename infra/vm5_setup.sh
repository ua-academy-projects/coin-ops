#!/bin/bash

set -e
WORKING_DIR="/home/vagrant/shared_folder/database"

# vm 5 - db
sudo apt install -y postgresql
export $(grep -v '^#' "$WORKING_DIR/database.env" | tr -d '\r' | xargs)

# postgres cannot read init.sql from the synced folder (Permission denied on many providers).
# Open the file as vagrant and pipe SQL into psql.
sudo -u postgres psql \
  -v user_name="$PGUSER" \
  -v user_password="'$PGPASSWORD'" \
  -f - < "$WORKING_DIR/init.sql"

sudo -u postgres psql -d coinops_db -c '\dt'
echo "host    all             all             10.10.1.0/24            scram-sha-256" >> /etc/postgresql/16/main/pg_hba.conf
echo "listen_addresses = '*'" >> /etc/postgresql/16/main/postgresql.conf
sudo systemctl restart postgresql
echo "PostgreSQL restarted after listen/pg_hba changes."
sudo -u postgres psql -d coinops_db -c '\dt'

echo -e "\033[0;32mVM 5 success setup. PostgreSQL is running..."
