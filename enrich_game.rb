require 'open-uri'
require 'nokogiri'
require 'json'

GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def parse_game_sheet(game_id)
  url = "#{GAME_REPORT_BASE}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc = Nokogiri::HTML(html)
  debug = ENV["DEBUG"] == "true"

  rows = doc.css('table').find { |t| t.text.include?('Goals') && t.text.include?('Assists') }&.css('tr')&.drop(1) || []

  puts "🧪 Found #{rows.size} scoring rows" if debug

  if rows.empty?
    File.write("/tmp/debug_#{game_id}.html", html)
    puts "⚠️ No scoring rows found — dumped HTML to /tmp/debug_#{game_id}.html" if debug
  end

  # 🧠 Determine Greenville's home/away role from first goal row
  first_team_code = rows.first&.css('td')&.at(3)&.text&.strip
  greenville_is_away = case first_team_code
    when "GVL" then false
    when "UTA", "SAV", "ORL", "ATL", "NOR", "JAX", "SC", "FLA", "IDH", "NFL", "CIN", "TOL", "IND", "KAL", "FW", "WOR", "ADK", "REA", "WHL", "TUL", "KC", "WIC", "RC", "IA", "ALN", "TRO", "WIC", "WHE"
      true
    else
      puts "⚠️ Unknown team code in first goal row: #{first_team_code}" if debug
      false # default to home
  end

  puts "🧠 First goal row team code: #{first_team_code}" if debug
  puts "🏠 Greenville is away? #{greenville_is_away}" if debug

  home_goals, away_goals = [], []

  rows.each do |row|
    tds = row.css('td')
    next unless tds.size >= 7

    team = tds[3].text.strip
    scorer = tds[5].text.split('(').first.strip
    assists = tds[6].text.strip
    entry = assists.empty? ? "#{scorer} (unassisted)" : "#{scorer} (#{assists})"

    puts "→ team: #{team}, scorer: #{scorer}, assists: #{assists}, entry: #{entry}" if debug

    if team == "GVL"
      if greenville_is_away
        away_goals << entry
        puts "🏒 Assigned to away_goals" if debug
      else
        home_goals << entry
        puts "🏒 Assigned to home_goals" if debug
      end
    else
      if greenville_is_away
        home_goals << entry
        puts "🏒 Assigned to home_goals" if debug
      else
        away_goals << entry
        puts "🏒 Assigned to away_goals" if debug
      end
    end
  end

  # 🧠 Parse scoring summary table to get final totals
  summary_table = doc.css('table').find { |t| t.text.include?('Scoring') && t.text.include?('SO') && t.text.include?('T') }
  summary_rows = summary_table&.css('tr')&.drop(1) || []

  greenville_total = nil
  opponent_total = nil

  summary_rows.each do |row|
    cells = row.css('td').map { |td| td.text.strip }
    next unless cells.size >= 7

    team_name = cells[0]
    total = cells[-1].to_i

    if team_name.include?("Greenville")
      greenville_total = total
    else
      opponent_total = total
    end
  end

  # Fallback if summary table fails
  greenville_total ||= greenville_is_away ? away_goals.size : home_goals.size
  opponent_total  ||= greenville_is_away ? home_goals.size : away_goals.size

  # 🧠 Determine result
  swamp_score = greenville_is_away ? greenville_total : opponent_total
  opponent_score = greenville_is_away ? opponent_total : greenville_total

  result =
    if swamp_score > opponent_score
      "W"
    elsif swamp_score < opponent_score
      "L"
    else
      nil
    end

  status = "Final"
  status += " (SO)" if summary_table&.text&.include?("SO")

  {
    game_id: game_id.to_i,
    home_score: greenville_is_away ? opponent_total : greenville_total,
    away_score: greenville_is_away ? greenville_total : opponent_total,
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
