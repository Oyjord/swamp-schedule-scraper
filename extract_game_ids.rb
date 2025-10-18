require 'open-uri'
require 'json'

FEED_URL = "https://lscluster.hockeytech.com/feed/index.php?feed=statviewfeed&view=schedule&team=-1&season=73&month=-1&location=homeaway&key=2c2b89ea7345cae8&client_code=echl&site_id=0&league_id=1&conference_id=-1&division_id=-1&lang=en&callback=angular.callbacks._0"

def fetch_schedule
  raw = URI.open(FEED_URL).read.strip

  # Remove the outer parentheses: ([ ... ])
  if raw.start_with?('([') && raw.end_with?('])')
    json_text = raw[1..-2]  # Strip the outer ( and )
  else
    raise "Unexpected feed format"
  end

  JSON.parse(json_text)
end

def extract_swamp_games(rows)
  rows.select do |row|
    row["homeTeamName"] == "Greenville Swamp Rabbits" || row["visitingTeamName"] == "Greenville Swamp Rabbits"
  end.map do |game|
    {
      game_id: game["gameId"].to_i,
      date: game["date"],
      opponent: game["homeTeamName"] == "Greenville Swamp Rabbits" ? game["visitingTeamName"] : game["homeTeamName"],
      location: game["homeTeamName"] == "Greenville Swamp Rabbits" ? "Home" : "Away"
    }
  end
end

data = fetch_schedule
swamp_games = extract_swamp_games(data["rows"])
File.write("swamp_game_ids.json", JSON.pretty_generate(swamp_games))
puts "✅ Extracted #{swamp_games.size} Swamp Rabbits games to swamp_game_ids.json"
