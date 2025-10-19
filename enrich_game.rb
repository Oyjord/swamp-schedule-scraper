require 'open-uri'
require 'nokogiri'
require 'json'

GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def parse_game_sheet(game_id, location)
  url = "#{GAME_REPORT_BASE}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc = Nokogiri::HTML(html)
  debug = ENV["DEBUG"] == "true"

  # ✅ Parse GOALS table
  rows = doc.css('table').find do |table|
    header = table.at_css('tr')
    header && header.text.include?('Goals') && header.text.include?('Assists')
  end&.css('tr')&.drop(1) || []

  puts "🧪 Found #{rows.size} scoring rows" if debug

  if rows.empty?
    File.write("/tmp/debug_#{game_id}.html", html)
    puts "⚠️ No scoring rows found — dumped HTML to /tmp/debug_#{game_id}.html" if debug
  end

  home_goals, away_goals = [], []

  rows.each do |row|
    tds = row.css('td')
    next unless tds.size >= 7

    team = tds[3].text.strip
    scorer = tds[5].text.split('(').first.strip
    assists = tds[6].text.strip
    entry = assists.empty? ? "#{scorer} (unassisted)" : "#{scorer} (#{assists})"

    puts "→ team: #{team.inspect}, scorer: #{scorer.inspect}, assists: #{assists.inspect}, entry: #{entry.inspect}" if debug

    if team == "GVL"
      home_goals << entry
    elsif team
      away_goals << entry
    end
  end

  # ✅ Parse SCORING table for final score and OT/SO
  scoring_table = doc.css('table').find { |t| t.text.include?('SCORING') && t.text.include?('T') }
  scoring_rows = scoring_table&.css('tbody tr') || []
  header_cells = scoring_table&.at_css('thead')&.css('tr')&.first&.css('th')&.map(&:text)&.map(&:strip) || []

  home_score = nil
  away_score = nil
  overtime_type = nil

  if scoring_rows.size >= 2
    away_cells = scoring_rows[0].css('td').map(&:text).map(&:strip)
    home_cells = scoring_rows[1].css('td').map(&:text).map(&:strip)

    away_score = away_cells.last.to_i
    home_score = home_cells.last.to_i

    if header_cells.include?("SO")
      overtime_type = "SO"
    elsif header_cells.any? { |h| h.start_with?("OT") }
      overtime_type = "OT"
    end

    puts "📊 SCORING → Home: #{home_score}, Away: #{away_score}, OT Type: #{overtime_type}" if debug
  end

  # ✅ Result logic based on location and final score
  greenville_score = location == "Home" ? home_score : away_score
  opponent_score = location == "Home" ? away_score : home_score

  result =
    if greenville_score > opponent_score
      "W"
    elsif greenville_score < opponent_score
      "L"
    else
      nil
    end

  result += "(#{overtime_type})" if result && overtime_type

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
puts JSON.pretty_generate(enriched) if enriched
