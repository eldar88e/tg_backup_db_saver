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

def run!(cmd)
  puts "▶ #{cmd}"
  success = system(cmd)
  abort("❌ Command failed") unless success
end

def archive_and_compress(dir, archive, name)
  puts "📦 Archiving #{name}..."
  run!("tar -czf #{archive} -C #{dir} .")
end

def tg_file_send(archive_path, name)
  puts "📤 Sending #{name} to Telegram..."
  Telegram::Bot::Client.run(TOKEN) do |bot|
    bot.api.send_document(
      chat_id: CHAT_ID,
      document: Faraday::UploadIO.new(archive_path, 'application/gzip'),
      caption: "Backup for #{name}"
    )
  rescue StandardError => e
    puts "❌ #{e.message}"
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
