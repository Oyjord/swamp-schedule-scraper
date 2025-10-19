require 'open-uri'
require 'nokogiri'
require 'json'

GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def parse_game_sheet(game_id)
  url = "#{GAME_REPORT_BASE}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc = Nokogiri::HTML(html)
  debug = ENV["DEBUG"] == "true"

  # 🧠 Parse scoring summary table to determine team roles and final totals
  summary_table = doc.css('table').find { |t| t.text.include?('Scoring') && t.text.include?('SO') && t.text.include?('T') }
  summary_rows = summary_table&.css('tr')&.drop(1) || []

  greenville_is_home = nil
  greenville_total = nil
  opponent_total = nil
  home_team_name = nil
  away_team_name = nil

  if summary_rows.size >= 2
    home_team_name = summary_rows[0].css('td')[0]&.text&.strip
    away_team_name = summary_rows[1].css('td')[0]&.text&.strip
    home_total = summary_rows[0].css('td')[-1]&.text&.strip.to_i
    away_total = summary_rows[1].css('td')[-1]&.text&.strip.to_i

    greenville_is_home = home_team_name&.include?("Greenville")
    greenville_total = greenville_is_home ? home_total : away_total
    opponent_total = greenville_is_home ? away_total : home_total

    puts "📊 Home: #{home_team_name} (#{home_total}), Away: #{away_team_name} (#{away_total})" if debug
    puts "🏠 Greenville is home? #{greenville_is_home}" if debug
  else
    puts "⚠️ Could not parse scoring summary table" if debug
  end

  # 🧩 Parse goal rows
  rows = doc.css('table').find { |t| t.text.include?('Goals') && t.text.include?('Assists') }&.css('tr')&.drop(1) || []
  puts "🧪 Found #{rows.size} scoring rows" if debug

  home_goals, away_goals = [], []

  rows.each do |row|
    tds = row.css('td')
    next unless tds.size >= 7

    team_code = tds[3].text.strip
    scorer = tds[5].text.split('(').first.strip
    assists = tds[6].text.strip
    entry = assists.empty? ? "#{scorer} (unassisted)" : "#{scorer} (#{assists})"

    # Assign based on team code and greenville_is_home
    if greenville_is_home.nil?
      puts "⚠️ Cannot assign goals — unknown home/away roles" if debug
      next
    end

    if team_code == "GVL"
      greenville_is_home ? home_goals << entry : away_goals << entry
      puts "🏒 GVL goal → #{greenville_is_home ? 'home_goals' : 'away_goals'}: #{entry}" if debug
    else
      greenville_is_home ? away_goals << entry : home_goals << entry
      puts "🏒 Opponent goal → #{greenville_is_home ? 'away_goals' : 'home_goals'}: #{entry}" if debug
    end
  end

  # 🧠 Determine result
  result =
    if greenville_total && opponent_total
      if greenville_total > opponent_total
        "W"
      elsif greenville_total < opponent_total
        "L"
      else
        nil
      end
    else
      nil
    end

  # 🧠 Determine overtime type
  overtime_type = nil
  if summary_table
    header = summary_table.css('tr').first&.text
    if header&.include?("SO")
      overtime_type = "SO"
    elsif header&.include?("OT")
      overtime_type = "OT"
    end
  end

  status = "Final"
  status += " (#{overtime_type})" if overtime_type

  {
    game_id: game_id.to_i,
    home_score: greenville_is_home ? greenville_total : opponent_total,
    away_score: greenville_is_home ? opponent_total : greenville_total,
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
if ARGV.empty?
  puts "Usage: ruby enrich_game.rb <game_id>"
  exit 1
end

game_id = ARGV[0]
enriched = parse_game_sheet(game_id)
puts JSON.pretty_generate(enriched) if enriched
