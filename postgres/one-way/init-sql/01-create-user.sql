CREATE USER db_username WITH PASSWORD 'password';

CREATE DATABASE db_name;

GRANT ALL PRIVILEGES ON DATABASE db_name TO db_username;

ALTER DATABASE db_name OWNER TO db_username;
