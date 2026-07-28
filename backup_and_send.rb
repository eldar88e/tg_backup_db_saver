# Telegram::Bot::Client.run(TOKEN) do |bot|
#   bot.listen do |message|
#     binding.irb # message.chat.id for read chat_id
#   end
# end

require 'yaml'
require 'fileutils'
require 'telegram/bot'

CONFIG   = YAML.load_file('backup.yml')
BASE_DIR = File.expand_path(__dir__)
TOKEN    = CONFIG['telegram']['bot_token']
CHAT_ID  = CONFIG['telegram']['chat_id']
MAX_THREADS = 3
MAX_TELEGRAM_FILE_SIZE = 45 * 1024 * 1024

def run!(cmd)
  puts "▶ #{cmd}"
  success = system(cmd)
  abort("❌ Command failed") unless success
end

def archive_and_compress(dir, archive, name)
  puts "📦 Archiving #{name}..."
  run!("tar -czf #{archive} -C #{dir} .")
end

def split_file(path)
  parts = []
  index = 1

  File.open(path, 'rb') do |source|
    until source.eof?
      part_path = format('%s.part%03d', path, index)

      File.open(part_path, 'wb') do |part|
        remaining = MAX_TELEGRAM_FILE_SIZE

        while remaining.positive?
          chunk = source.read([remaining, 1024 * 1024].min)
          break unless chunk

          part.write(chunk)
          remaining -= chunk.bytesize
        end
      end

      parts << part_path
      index += 1
    end
  end

  parts
end

def tg_file_send(archive_path, name)
  archive_size_mb = File.size(archive_path) / 1024.0 / 1024
  puts "📏 Archive size: #{archive_size_mb.round(2)} MB"

  files =
    if File.size(archive_path) <= MAX_TELEGRAM_FILE_SIZE
      [archive_path]
    else
      puts '✂️ Splitting archive into 45 MB parts...'
      split_file(archive_path)
    end

  Telegram::Bot::Client.run(TOKEN) do |bot|
    files.each_with_index do |file, index|
      puts "📤 Sending #{File.basename(file)}..."

      caption =
        if files.one?
          "Backup for #{name}"
        else
          "Backup for #{name}: part #{index + 1}/#{files.length}"
        end

      bot.api.send_document(
        chat_id: CHAT_ID,
        document: Faraday::UploadIO.new(
          file,
          'application/octet-stream',
          File.basename(file)
        ),
        caption: caption
      )
    end
  end

  puts "✅ Backup #{name} successfully sent"
rescue StandardError => e
  warn "❌ Telegram upload failed: #{e.message}"
  raise
ensure
  files&.each do |file|
    next if file == archive_path

    FileUtils.rm_f(file)
  end
end

def process_backup(b)
  name = b['name']
  puts "\n=== Backup: #{name} ==="

  backups_dir = "#{BASE_DIR}/backups/#{name}"
  FileUtils.mkdir_p(backups_dir)

  # Dir.chdir(b['workdir']) do
  #   run!(b['command'])
  #   dump_file = b['command'].match(/>\s*(\S+)/)[1]
  #   FileUtils.mv(File.join(b['workdir'], dump_file), File.join(backups_dir, "#{name}.sql"))
  # end

  dump_path = File.join(backups_dir, "#{name}.sql")
  dump_file = b['command'].match(/>\s*(\S+)/)[1]
  cmd = b['command'].sub(dump_file, dump_path)
  run!(cmd)

  archive_path = "#{BASE_DIR}/backups/#{name}.tar.gz"
  archive_and_compress(backups_dir, archive_path, name)
  tg_file_send(archive_path, name)
end

queue = Queue.new
CONFIG['backups'].each { |b| queue << b }

workers = Array.new(MAX_THREADS) do
  Thread.new do
    while (b = queue.pop(true) rescue nil)
      process_backup(b)
    end
  end
end

workers.each(&:join)

puts "\n✅ All backups done"
