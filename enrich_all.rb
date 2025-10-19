require 'json'

# --- Load game IDs and any existing data ---
game_ids = JSON.parse(File.read("swamp_game_ids.json"))
existing = File.exist?("swamp_schedule.json") ? JSON.parse(File.read("swamp_schedule.json")) : []

# Create a hash keyed by game_id for easy updates
existing_by_id = {}
existing.each { |g| existing_by_id[g["game_id"]] = g }

# --- Process each game ---
game_ids.each do |game|
  game_id = game["game_id"]
  puts "🔍 Enriching game #{game_id}..."

  # Run enrich_game.rb for this game
  enriched_output = `ruby enrich_game.rb #{game_id}`
  next if enriched_output.strip.empty?

  # Try parsing the JSON safely
  begin
    data = JSON.parse(enriched_output)
  rescue JSON::ParserError
    warn "⚠️ Skipping #{game_id} (invalid JSON output)"
    # Add placeholder if JSON parsing failed
    existing_by_id[game_id] ||= {
      "game_id" => game_id,
      "date" => game["date"],
      "opponent" => game["opponent"],
      "location" => game["location"],
      "status" => "Unavailable",
      "game_report_url" => nil
    }
    next
  end

  next unless data # skip nil results

  # Build the enriched game entry
  existing_by_id[game_id] = {
    "game_id" => game_id,
    "date" => game["date"],
    "opponent" => game["opponent"],
    "location" => game["location"],
    "status" => data["status"] || "Final",
    "home_score" => data["home_score"],
    "away_score" => data["away_score"],
    "home_goals" => data["home_goals"],
    "away_goals" => data["away_goals"],
    "result" => data["result"],
    "overtime_type" => data["overtime_type"],
    "game_report_url" => data["game_report_url"]
  }
end

# --- Sort safely by date (handle nil dates) ---
sorted_games = existing_by_id.values.sort_by { |g| g["date"] || "" }

# --- Write updated file ---
File.write("swamp_schedule.json", JSON.pretty_generate(sorted_games))
puts "✅ Updated swamp_schedule.json with #{existing_by_id.size} games"
