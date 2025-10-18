require 'open-uri'
require 'nokogiri'
require 'json'

LIVEWIRE_JS = "https://echl.com/livewire/livewire.js?id=90730a3b0e7144480175"
GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def fetch_schedule
  raw = URI.open(LIVEWIRE_JS).read
  json_text = raw.sub("window.livewireData = ", "").strip
  JSON.parse(json_text)["schedule"]
end

def extract_game_id(game_center_url)
  html = URI.open(game_center_url).read
  doc = Nokogiri::HTML(html)
  link = doc.css('a[href*="game_reports/official-game-report.php"]').find { |a| a['href'] =~ /game_id=(\d+)/ }
  link&.[]('href')&.match(/game_id=(\d+)/)&.captures&.first
rescue => e
  puts "⚠️ Failed to extract game_id from #{game_center_url}: #{e}"
  nil
end

def parse_game_sheet(game_id)
  url = "#{GAME_REPORT_BASE}#{game_id}"
  html = URI.open(url).read
  doc = Nokogiri::HTML(html)

  rows = doc.css('table').select { |t| t.text.include?("Scoring Summary") }.flat_map { |t| t.css('tr') }
  home_goals, away_goals = [], []

  rows.each do |row|
    cells = row.css('td').map(&:text).map(&:strip)
    next unless cells.size >= 5
    team = cells[1]
    scorer = cells[3].split('(').first.strip
    assists = cells[4].strip
    entry = assists.empty? ? "#{scorer} (unassisted)" : "#{scorer} (#{assists})"

    if team == "GVL"
      home_goals << entry
    elsif team != "GVL"
      away_goals << entry
    end
  end

  score = { home: home_goals.size, away: away_goals.size }
  { score:, home_goals:, away_goals: }
rescue => e
  puts "⚠️ Failed to parse game sheet for game_id #{game_id}: #{e}"
  { score: { home: 0, away: 0 }, home_goals: [], away_goals: [] }
end

def load_existing
  File.exist?("swamp_schedule.json") ? JSON.parse(File.read("swamp_schedule.json")) : []
end

def save_schedule(games)
  File.write("swamp_schedule.json", JSON.pretty_generate(games))
  puts "✅ Saved swamp_schedule.json with #{games.size} games"
end

existing = load_existing
existing_by_id = {}
existing.each { |g| existing_by_id[g["game_id"]] = g }

schedule = fetch_schedule
swamp_games = schedule.select do |g|
  g["home_team"] == "Greenville Swamp Rabbits" || g["away_team"] == "Greenville Swamp Rabbits"
end

swamp_games.each do |game|
  date = game["date"]
  opponent = game["home_team"] == "Greenville Swamp Rabbits" ? game["away_team"] : game["home_team"]
  location = game["home_team"] == "Greenville Swamp Rabbits" ? "Home" : "Away"
  url = game["game_center_url"]
  next unless url

  game_id = extract_game_id(url)
  next unless game_id

  enriched = parse_game_sheet(game_id)
  existing_by_id[game_id.to_i] = {
    game_id: game_id.to_i,
    date: Date.parse(date).strftime("%a, %b %d"),
    status: "Final",
    home_team: game["home_team"],
    away_team: game["away_team"],
    home_score: enriched[:score][:home],
    away_score: enriched[:score][:away],
    game_report_url: "#{GAME_REPORT_BASE}#{game_id}",
    home_goals: enriched[:home_goals],
    away_goals: enriched[:away_goals]
  }
end

save_schedule(existing_by_id.values.sort_by { |g| g["date"] })
