require 'open-uri'
require 'nokogiri'
require 'json'

GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def parse_game_sheet(game_id)
  url = "#{GAME_REPORT_BASE}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc  = Nokogiri::HTML(html)
  debug = ENV["DEBUG"] == "true"

  # --- Extract team totals from the SCORING table ---
  scoring_table = doc.css('table').find { |t| t.text.include?("SCORING") }
  unless scoring_table
    puts "⚠️ No scoring table found for #{game_id}"
    return nil
  end

  rows = scoring_table.css('tr')[2..3] || []
  greenville_row = rows.find { |r| r.text.include?("Greenville") }
  savannah_row   = rows.find { |r| r.text.include?("Savannah") }

  home_name  = "Savannah"
  away_name  = "Greenville"

  away_score = greenville_row&.css('td')&.last&.text&.to_i || 0
  home_score = savannah_row&.css('td')&.last&.text&.to_i || 0

  puts "🏒 Scores — #{away_name}: #{away_score}, #{home_name}: #{home_score}" if debug

  # --- Parse the individual goals ---
  goal_table = doc.css('table').find do |t|
    header = t.at_css('tr')
    header && header.text.include?('Goals') && header.text.include?('Assists')
  end
  goal_rows = goal_table ? goal_table.css('tr')[1..] : []

  home_goals, away_goals = [], []

  goal_rows.each do |row|
    tds = row.css('td')
    next unless tds.size >= 7
    team    = tds[3].text.strip
    scorer  = tds[5].text.split('(').first.strip
    assists = tds[6].text.strip
    entry   = assists.empty? ? "#{scorer} (unassisted)" : "#{scorer} (#{assists})"

    if team == "GVL" # Greenville
      away_goals << entry
    elsif team == "SAV" # Savannah
      home_goals << entry
    end
  end

  # --- Detect overtime / shootout ---
  overtime_type = nil
  overtime_type = "SO" if doc.text.include?("SHOOTOUT")
  overtime_type ||= "OT" if scoring_table.text.include?("OT1")

  # --- Adjust final score if shootout winner ---
  if overtime_type == "SO"
    if away_score > home_score
      away_score += 1
    elsif home_score > away_score
      home_score += 1
    end
  end

  # --- Determine result string ---
  if away_score > home_score
    diff_str = "#{away_score}-#{home_score}"
    result = overtime_type ? "W(#{overtime_type}) #{diff_str}" : "W #{diff_str}"
  elsif away_score < home_score
    diff_str = "#{away_score}-#{home_score}"
    result = overtime_type ? "L(#{overtime_type}) #{diff_str}" : "L #{diff_str}"
  else
    result = "T"
  end

  {
    game_id: game_id.to_i,
    date: "Oct. 18, 2025",
    home_team: home_name,
    away_team: away_name,
    home_score: home_score,
    away_score: away_score,
    home_goals: home_goals,
    away_goals: away_goals,
    game_report_url: url,
    status: "Final",
    result: result,
    overtime_type: overtime_type
  }
rescue => e
  puts "⚠️ Failed to parse game sheet for game_id #{game_id}: #{e}"
  nil
end

# --- CLI entrypoint ---
if ARGV.empty?
  puts "Usage: ruby enrich_game.rb <game_id>"
  exit 1
end

game_id = ARGV[0]
data = parse_game_sheet(game_id)
puts JSON.pretty_generate(data) if data
