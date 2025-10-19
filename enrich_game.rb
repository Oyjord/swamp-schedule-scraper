require 'open-uri'
require 'nokogiri'
require 'json'

GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def parse_game_sheet(game_id, _location, _opponent)
  url = "#{GAME_REPORT_BASE}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc = Nokogiri::HTML(html)
  debug = ENV["DEBUG"] == "true"

  home_score = nil
  away_score = nil
  overtime_type = nil
  greenville_is_home = nil

  # 🧠 Extract final scores from SCORING table
  score_table = doc.css('table').find { |t| t.text.include?('SCORING') && t.text.include?('T') }
  score_rows = score_table&.css('tr')&.drop(1) || []

  if score_rows.size >= 2
    away_cells = score_rows[0].css('td').map(&:text).map(&:strip)
    home_cells = score_rows[1].css('td').map(&:text).map(&:strip)

    away_team_name = away_cells[0]
    home_team_name = home_cells[0]

    if home_team_name.include?("Greenville")
      greenville_is_home = true
      home_score = home_cells[-1].to_i
      away_score = away_cells[-1].to_i
    elsif away_team_name.include?("Greenville")
      greenville_is_home = false
      home_score = home_cells[-1].to_i
      away_score = away_cells[-1].to_i
    else
      puts "⚠️ Greenville not found in SCORING table" if debug
    end

    puts "📊 SCORING table → Away: #{away_team_name} #{away_score}, Home: #{home_team_name} #{home_score}" if debug
    puts "🏠 Greenville is home? #{greenville_is_home}" if debug

    # 🧠 Detect OT/SO only if columns exist
    header_cells = score_table.css('tr').first.css('td').map(&:text).map(&:strip)
    overtime_type = "SO" if header_cells.any? { |h| h == "SO" }
    overtime_type = "OT" if header_cells.any? { |h| h == "OT1" } && overtime_type.nil?
  else
    puts "⚠️ SCORING table not found or incomplete" if debug
  end

  # 🧩 Parse goal rows from <tbody>
  goal_table = doc.css('table').find { |t| t.text.include?('Goals') && t.text.include?('Assists') }
  goal_rows = goal_table&.css('tbody tr') || []

  home_goals, away_goals = [], []

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
      puts "⚠️ Cannot assign goals — Greenville role unknown" if debug
      next
    end

    if team_code == "GVL"
      greenville_is_home ? home_goals << entry : away_goals << entry
    else
      greenville_is_home ? away_goals << entry : home_goals << entry
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
