require 'open-uri'
require 'nokogiri'
require 'json'

GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def parse_game_sheet(game_id, location, opponent)
  url = "#{GAME_REPORT_BASE}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc = Nokogiri::HTML(html)
  debug = ENV["DEBUG"] == "true"

  greenville_is_home = location == "Home"
  greenville_is_away = location == "Away"

  # 🧠 Parse scoring summary table
  summary_table = doc.css('table').find { |t| t.text.include?('Scoring') && t.text.include?('T') }
  summary_rows = summary_table&.css('tr')&.drop(1) || []

  home_score = nil
  away_score = nil
  overtime_type = nil

  if summary_rows.size >= 2
    home_cells = summary_rows[0].css('td')
    away_cells = summary_rows[1].css('td')

    home_score = home_cells[-1]&.text&.strip.to_i
    away_score = away_cells[-1]&.text&.strip.to_i

    header_text = summary_table.css('tr').first&.text || ""
    overtime_type = "SO" if header_text.include?("SO")
    overtime_type = "OT" if header_text.include?("OT") && !header_text.include?("SO")

    puts "📊 Parsed scores — Home: #{home_score}, Away: #{away_score}" if debug
    puts "⏱️ Overtime type: #{overtime_type || 'none'}" if debug
  else
    puts "⚠️ Scoring summary table not found or incomplete" if debug
  end

  # 🧩 Parse goal rows
  goal_table = doc.css('table').find { |t| t.text.include?('Goals') && t.text.include?('Assists') }
  goal_rows = goal_table&.css('tr')&.drop(1) || []

  home_goals, away_goals = [], []

  goal_rows.each do |row|
    tds = row.css('td')
    next unless tds.size >= 7

    team_code = tds[3].text.strip
    scorer = tds[5].text.split('(').first.strip
    assists = tds[6].text.strip
    entry = assists.empty? ? "#{scorer} (unassisted)" : "#{scorer} (#{assists})"

    if team_code == "GVL"
      if greenville_is_home
        home_goals << entry
        puts "🏒 GVL goal → home_goals: #{entry}" if debug
      else
        away_goals << entry
        puts "🏒 GVL goal → away_goals: #{entry}" if debug
      end
    else
      if greenville_is_home
        away_goals << entry
        puts "🏒 Opponent goal → away_goals: #{entry}" if debug
      else
        home_goals << entry
        puts "🏒 Opponent goal → home_goals: #{entry}" if debug
      end
    end
  end

  # 🧠 Determine result from Greenville’s perspective
  greenville_score = greenville_is_home ? home_score : away_score
  opponent_score = greenville_is_home ? away_score : home_score

  result =
    if greenville_score && opponent_score
      if greenville_score > opponent_score
        "W"
      elsif greenville_score < opponent_score
        "L"
      else
        nil
      end
    else
      nil
    end

  status = "Final"
  status += " (#{overtime_type})" if overtime_type

  {
    game_id: game_id.to_i,
    home_score: home_score,
    away_score: away_score,
    home_goals: home_goals,
    away_goals: away_goals,
    status: status,
    result: result,
    overtime_type: overtime_type,
    game_report_url: url
  }
rescue => e
  puts "⚠️ Failed to parse game sheet for game_id #{game_id}: #{e}"
  nil
end

# ✅ Final execution block
if ARGV.size < 3
  puts "Usage: ruby enrich_game.rb <game_id> <location: Home|Away> <opponent>"
  exit 1
end

game_id = ARGV[0]
location = ARGV[1]
opponent = ARGV[2]
enriched = parse_game_sheet(game_id, location, opponent)
puts JSON.pretty_generate(enriched) if enriched
