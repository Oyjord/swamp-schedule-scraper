require 'json'

game_ids = JSON.parse(File.read("swamp_game_ids.json"))
existing = File.exist?("swamp_schedule.json") ? JSON.parse(File.read("swamp_schedule.json")) : []
existing_by_id = {}
existing.each { |g| existing_by_id[g["game_id"]] = g }

game_ids.each do |game|
  game_id = game["game_id"]
  puts "🔍 Enriching game #{game_id}..."

  enriched = `ruby enrich_game.rb #{game_id}`
  next if enriched.strip.empty?

  begin
    data = JSON.parse(enriched)
  rescue JSON::ParserError => e
    puts "⚠️ Failed to parse game #{game_id}: #{e}"
    next
  end

  existing_by_id[game_id] = {
    game_id: game_id,
    date: game["date"],
    opponent: game["opponent"],
    location: game["location"],
    status: "Final",
    result: data["result"],
    overtime_type: data["overtime_type"],
    home_score: data["home_score"],
    away_score: data["away_score"],
    home_goals: data["home_goals"],
    away_goals: data["away_goals"],
    game_report_url: data["game_report_url"]
  }
end

File.write("swamp_schedule.json", JSON.pretty_generate(existing_by_id.values.sort_by { |g| g["date"] }))
puts "✅ Updated swamp_schedule.json with #{existing_by_id.size} games"
