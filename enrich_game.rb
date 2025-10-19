require 'open-uri'
require 'nokogiri'
require 'json'

GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def parse_game_sheet(game_id)
  url = "#{GAME_REPORT_BASE}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc = Nokogiri::HTML(html)
  debug = ENV["DEBUG"] == "true"

  title = doc.at('title')&.text || ""
  is_greenville_home = title.include?("Greenville") && !title.include?("at")
  greenville_is_away = title.include?("Greenville at")

  home_goals, away_goals = [], []

  rows = doc.css('table').find { |t| t.text.include?('Goals') && t.text.include?('Assists') }&.css('tr')&.drop(1) || []

  rows.each do |row|
    tds = row.css('td')
    next unless tds.size >= 7

    team = tds[3].text.strip
    scorer = tds[5].text.split('(').first.strip
    assists = tds[6].text.strip
    entry = assists.empty? ? "#{scorer} (unassisted)" : "#{scorer} (#{assists})"

    if team == "GVL"
      greenville_is_away ? away_goals << entry : home_goals << entry
    elsif team == "SAV"
      greenville_is_away ? home_goals << entry : away_goals << entry
    end
  end

  # 🧠 Detect shootout result
  shootout_table = doc.css('table').find { |t| t.text.include?('SHOOTOUT') }
  shootout_rows = shootout_table&.css('tr')&.select { |tr| tr.text.include?('Yes') } || []
  greenville_so_goals = shootout_rows.count { |r| r.text.include?('Greenville') && r.text.include?('Yes') }
  savannah_so_goals = shootout_rows.count { |r| r.text.include?('Savannah') && r.text.include?('Yes') }

  greenville_total = greenville_is_away ? away_goals.size : home_goals.size
  savannah_total = greenville_is_away ? home_goals.size : away_goals.size

  if greenville_so_goals != savannah_so_goals
    if greenville_so_goals > savannah_so_goals
      greenville_total += 1
      result = greenville_is_away ? "W(SO)" : "L(SO)"
    else
      savannah_total += 1
      result = greenville_is_away ? "L(SO)" : "W(SO)"
    end
    status = "Final (SO)"
  else
    result = nil
    status = "Final"
  end

  {
    game_id: game_id.to_i,
    home_score: greenville_is_away ? savannah_total : greenville_total,
    away_score: greenville_is_away ? greenville_total : savannah_total,
    home_goals: greenville_is_away ? home_goals : away_goals,
    away_goals: greenville_is_away ? away_goals : home_goals,
    status: status,
    result: result,
    game_report_url: url
  }
rescue => e
  puts "⚠️ Failed to parse game sheet for game_id #{game_id}: #{e}"
  nil
end

# ✅ Final execution block
if ARGV.empty?
  puts "Usage: ruby enrich_game.rb <game_id>"
  exit 1
end

game_id = ARGV[0]
enriched = parse_game_sheet(game_id)
puts JSON.pretty_generate(enriched) if enriched
