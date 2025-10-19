require 'open-uri'
require 'nokogiri'
require 'json'

BASE_URL = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def parse_game(game_id, _location, _opponent)
  url = "#{BASE_URL}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc = Nokogiri::HTML(html)

  home_score = nil
  away_score = nil
  greenville_is_home = nil
  home_goals = []
  away_goals = []

  # ✅ SCORING table: top row = away, bottom row = home
  scoring_table = doc.css('table').find { |t| t.text.include?('SCORING') && t.text.include?('T') }
  scoring_rows = scoring_table&.css('tbody tr') || []

  if scoring_rows.size >= 2
    away_team = scoring_rows[0].css('td')[0].text.strip
    home_team = scoring_rows[1].css('td')[0].text.strip
    away_score = scoring_rows[0].css('td')[-1].text.strip.to_i
    home_score = scoring_rows[1].css('td')[-1].text.strip.to_i

    greenville_is_home = home_team.include?("Greenville")

    puts "📊 SCORING → Away: #{away_team} #{away_score}, Home: #{home_team} #{home_score}"
    puts "🏠 Greenville is home? #{greenville_is_home}"
  else
    puts "⚠️ SCORING table not found or incomplete"
  end

  # ✅ GOALS table: parse <tbody> rows only
  goal_table = doc.css('table').find { |t| t.text.include?('Goals') && t.text.include?('Assists') }
  goal_rows = goal_table&.css('tbody tr') || []

  puts "🧪 Found #{goal_rows.size} goal rows"

  goal_rows.each do |row|
    tds = row.css('td')
    next unless tds.size >= 7

    team_code = tds[3].text.strip
    scorer_raw = tds[5].text.strip
    next if scorer_raw.empty? || scorer_raw.include?("Goals")

    scorer = scorer_raw.split('(').first.strip
    assists = tds[6].text.strip.gsub(/\u00A0/, '').strip
    entry = assists.empty? ? "#{scorer} (unassisted)" : "#{scorer} (#{assists})"

    if greenville_is_home.nil?
      puts "⚠️ Cannot assign goals — Greenville role unknown"
      next
    end

    if team_code == "GVL"
      greenville_is_home ? home_goals << entry : away_goals << entry
    else
      greenville_is_home ? away_goals << entry : home_goals << entry
    end
  end

  # ✅ Result logic
  greenville_score = greenville_is_home ? home_score : away_score
  opponent_score = greenville_is_home ? away_score : home_score

  result =
    if greenville_score && opponent_score
      greenville_score > opponent_score ? "W" : greenville_score < opponent_score ? "L" : nil
    else
      nil
    end

  {
    game_id: game_id.to_i,
    home_score: home_score,
    away_score: away_score,
    home_goals: home_goals,
    away_goals: away_goals,
    status: "Final",
    result: result,
    overtime_type: nil,
    game_report_url: url
  }
rescue => e
  puts "⚠️ Error parsing game #{game_id}: #{e}"
  nil
end

# ✅ CLI entry
if ARGV.size < 3
  puts "Usage: ruby enrich_game.rb <game_id> <location> <opponent>"
  exit 1
end

game_id = ARGV[0]
location = ARGV[1]
opponent = ARGV[2]
parsed = parse_game(game_id, location, opponent)
if parsed
  puts JSON.pretty_generate(parsed)
  puts "✅ JSON written for game #{game_id}"
else
  puts "⚠️ No data parsed for game #{game_id}"
end
