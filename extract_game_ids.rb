require 'open-uri'
require 'json'

FEED_URL = "https://lscluster.hockeytech.com/feed/index.php?feed=statviewfeed&view=schedule&team=-1&season=73&month=-1&location=homeaway&key=2c2b89ea7345cae8&client_code=echl&site_id=0&league_id=1&conference_id=-1&division_id=-1&lang=en&callback=angular.callbacks._0"

def fetch_schedule
  raw = URI.open(FEED_URL).read.strip

  # Debug: show first 100 chars of raw feed
  puts "🔍 Raw feed starts with: #{raw[0..100]}"

  # Step 1: Strip JSONP wrapper
  if raw.start_with?('angular.callbacks._0(')
    raw = raw.sub(/^angular\.callbacks\._0/, '').sub(/\s*$/, '')
  end

  # Step 2: Strip extra parentheses wrapper: ([ ... ])
  if raw.start_with?('([') && raw.end_with?('])')
    raw = raw[1..-2]
  end

  JSON.parse(raw)
end

def extract_swamp_games(rows)
  rows.select do |row|
    r = row["row"]
    r["home_team_city"] == "Greenville" || r["visiting_team_city"] == "Greenville"
  end.map do |game|
    r = game["row"]
    p = game["prop"]
    {
      game_id: p["game_center"]["gameLink"].to_i,
      date: r["date"],
      opponent: r["home_team_city"] == "Greenville" ? r["visiting_team_city"] : r["home_team_city"],
      location: r["home_team_city"] == "Greenville" ? "Home" : "Away"
    }
  end
end

data = fetch_schedule
rows = data[0]["sections"][0]["data"]
swamp_games = extract_swamp_games(rows)

File.write("swamp_game_ids.json", JSON.pretty_generate(swamp_games))
puts "✅ Extracted #{swamp_games.size} Swamp Rabbits games to swamp_game_ids.json"
