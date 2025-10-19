require 'json'

puts "🟡 Starting enrichment at #{Time.now}"

game_ids = JSON.parse(File.read("swamp_game_ids.json"))
existing = File.exist?("swamp_schedule.json") ? JSON.parse(File.read("swamp_schedule.json")) : []
existing_by_id = {}
existing.each { |g| existing_by_id[g["game_id"]] = g }

puts "🟡 Found #{game_ids.size} games to enrich"

game_ids.each do |game|
  game_id = game["game_id"]
  location = game["location"]
  puts "🔍 Enriching game #{game_id}..."

  enriched = `ruby enrich_game.rb #{game_id} #{location}`
  next if enriched.strip.empty?

  begin
    data = JSON.parse(enriched)
  rescue JSON::ParserError => e
    puts "⚠️ Failed to parse game #{game_id}: #{e}"
    next
  end

  puts "📦 Enriched game #{game_id}: result=#{data['result']}, OT=#{data['overtime_type']}"

  existing_by_id[game_id] = {
    game_id: game_id,
    date: game["date"],
    opponent: game["opponent"],
    location: location,
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

puts "🧪 Preparing to write swamp_schedule.json..."
puts "🧪 Sample game 24312: #{existing_by_id[24312].inspect}" if existing_by_id[24312]

begin
  File.write("swamp_schedule.json", JSON.pretty_generate(existing_by_id.values.sort_by { |g| g["date"] }))
  puts "✅ Wrote swamp_schedule.json with #{existing_by_id.size} games at #{Time.now}"
rescue => e
  puts "❌ Failed to write swamp_schedule.json: #{e}"
end
