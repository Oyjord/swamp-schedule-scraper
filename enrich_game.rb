require 'json'
require 'open3'
require 'digest'

game_ids = JSON.parse(File.read("swamp_game_ids.json"))
existing = File.exist?("swamp_schedule.json") ? JSON.parse(File.read("swamp_schedule.json")) : []
existing_by_id = {}
existing.each { |g| existing_by_id[g["game_id"]] = g }

game_ids.each do |game|
  game_id = game["game_id"]
  puts "🔍 Enriching game #{game_id}..."

  cmd = "ruby enrich_game.rb #{game_id} #{game["location"]} \"#{game["opponent"]}\""
  stdout, stderr, status = Open3.capture3(cmd)

  if !status.success? || stdout.strip.empty?
    puts "⚠️ Script failed or returned no output for game #{game_id}"
    puts "stderr:\n#{stderr}" unless stderr.strip.empty?
    next
  end

  begin
    data = JSON.parse(stdout)
  rescue JSON::ParserError => e
    puts "⚠️ Failed to parse game #{game_id}: #{e}"
    puts "Raw stdout:\n#{stdout}"
    puts "Raw stderr:\n#{stderr}" unless stderr.strip.empty?
    next
  end

  puts stderr unless stderr.strip.empty?  # ✅ Always show debug output
  puts "✅ Enriched game #{game_id}: #{data["result"] || "-"} (#{data["home_score"]}-#{data["away_score"]})"

  existing_by_id[game_id] = {
    game_id: game_id,
    date: game["date"],
    opponent: game["opponent"],
    location: game["location"],
    status: data["status"],
    result: data["result"],
    overtime_type: data["overtime_type"],
    home_score: data["home_score"],
    away_score: data["away_score"],
    home_goals: data["home_goals"],
    away_goals: data["away_goals"],
    game_report_url: data["game_report_url"]
  }
end

new_json = JSON.pretty_generate(existing_by_id.values.sort_by { |g| g["date"] })
old_json = File.exist?("swamp_schedule.json") ? File.read("swamp_schedule.json") : ""

if Digest::SHA256.hexdigest(new_json) != Digest::SHA256.hexdigest(old_json)
  File.write("swamp_schedule.json", new_json)
  puts "✅ Updated swamp_schedule.json with #{existing_by_id.size} games at #{Time.now}"
else
  puts "ℹ️ No changes detected — swamp_schedule.json remains unchanged"
end
