# Telegram DB Backup

The script for backing up, compressing and sending databases to Telegram.

## Dependencies

- Ruby 3.4.8
- fileutils
- telegram-bot-ruby
- yaml

## Installation

1. Clone repo
2. Copy `backup.yml.example` в `backup.yml`:
   ```bash
   cp backup.yml.example backup.yml
   ```

## Usage

Run:

```bash
ruby backup_and_send.rb
```

## Cron

Add to crontab:

```bash
0 3 * * * cd /path/to/backup_db_saver && ruby backup_and_send.rb >> /var/log/backup.log 2>&1
```

## For Example

### PostgreSQL (Docker)
```yaml
command: "docker exec container_name pg_dump -U username dbname > backup.sql"
```
