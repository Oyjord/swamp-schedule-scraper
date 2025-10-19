require 'open-uri'
require 'nokogiri'
require 'json'

GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def parse_game_sheet(game_id, location)
  url = "#{GAME_REPORT_BASE}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc = Nokogiri::HTML(html)

  # ✅ Parse SCORING table to detect OT/SO and shootout winner
  scoring_table = doc.css('table').find { |t| t.text.include?('SCORING') && t.text.include?('T') }
  scoring_rows = scoring_table&.css('tbody tr') || []
  header_cells = scoring_table&.at_css('thead')&.css('tr')&.first&.css('th')&.map(&:text)&.map(&:strip) || []

  overtime_type = nil
  shootout_winner = nil

  if scoring_table
    puts "🧪 SCORING header: #{header_cells.join(' | ')}"
    scoring_rows.each_with_index do |row, i|
      cells = row.css('td').map(&:text).map(&:strip)
      puts "🧪 Row #{i}: #{cells.join(' | ')}"
    end
  else
    puts "❌ No SCORING table found for game #{game_id}"
  end

  if scoring_rows.size >= 2 && header_cells.include?("SO")
    overtime_type = "SO"
    so_index = header_cells.index("SO")

    row1 = scoring_rows[0].css('td').map(&:text).map(&:strip)
    row2 = scoring_rows[1].css('td').map(&:text).map(&:strip)

    team1 = row1[0]
    team2 = row2[0]
    so1 = row1[so_index].to_i
    so2 = row2[so_index].to_i

    if team1.strip.downcase.include?("greenville") && so1 > 0
      shootout_winner = "GVL"
    elsif team2.strip.downcase.include?("greenville") && so2 > 0
      shootout_winner = "GVL"
    elsif !team1.strip.downcase.include?("greenville") && so1 > 0
      shootout_winner = "OPP"
    elsif !team2.strip.downcase.include?("greenville") && so2 > 0
      shootout_winner = "OPP"
    end
  elsif header_cells.any? { |h| h.start_with?("OT") }
    overtime_type = "OT"
  end

  # ✅ Parse GOALS table
  rows = doc.css('table').find do |table|
    header = table.at_css('tr')
    header && header.text.include?('Goals') && header.text.include?('Assists')
  end&.css('tr')&.drop(1) || []

  home_goals, away_goals = [], []

  rows.each do |row|
    tds = row.css('td')
    next unless tds.size >= 7

    team = tds[3].text.strip
    scorer = tds[5].text.split('(').first.strip
    assists = tds[6].text.strip
    entry = assists.empty? ? "#{scorer} (unassisted)" : "#{scorer} (#{assists})"

    if team == "GVL"
      home_goals << entry
    elsif team
      away_goals << entry
    end
  end

  home_score = home_goals.size
  away_score = away_goals.size

  greenville_score = location == "Home" ? home_score : away_score
  opponent_score = location == "Home" ? away_score : home_score

  result = nil
  if greenville_score > opponent_score
    result = "W"
  elsif greenville_score < opponent_score
    result = "L"
  elsif greenville_score == opponent_score && overtime_type == "SO"
    result = shootout_winner == "GVL" ? "W(SO)" : shootout_winner == "OPP" ? "L(SO)" : nil
  end

  {
    game_id: game_id.to_i,
    home_score: home_score,
    away_score: away_score,
    home_goals: home_goals,
    away_goals: away_goals,
    status: "Final",
    result: result,
    overtime_type: overtime_type,
    game_report_url: url
  }
rescue => e
  puts "⚠️ Failed to parse game sheet for game_id #{game_id}: #{e}"
  nil
end

if ARGV.size < 2
  puts "Usage: ruby enrich_game.rb <game_id> <location>"
  exit 1
end

game_id = ARGV[0]
location = ARGV[1]
enriched = parse_game_sheet(game_id, location)

# ✅ Only emit valid JSON once
puts JSON.pretty_generate(enriched) if enriched
