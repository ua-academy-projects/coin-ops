#!/bin/bash

WORKING_DIR="/home/working_dir"

# vm 5 - db
sudo apt install -y postgresql
cp -r "/home/shared_folder/database" "$WORKING_DIR"
export $(grep -v '^#' /home/working_dir/database.env | tr -d '\r' | xargs)
echo "DEBUG: $PGUSER"
echo "DEBUG: $PGPASSWORD"
sudo -u postgres psql \
  -v user_name="$PGUSER" \
  -v user_password="'$PGPASSWORD'" \
  -f "$WORKING_DIR/init.sql"

sudo -u postgres psql -d coinops_db -c '\dt'
echo "host    all             all             10.10.1.0/24            scram-sha-256" >> /etc/postgresql/16/main/pg_hba.conf
echo "listen_addresses = '*'" >> /etc/postgresql/16/main/postgresql.conf
sudo systemctl restart postgresql && echo "Success" || echo "Error"
sudo -u postgres psql -d coinops_db -c '\dt'

echo -e "\033[0;32mVM 5 success setup. PostgreSQL is running..."
