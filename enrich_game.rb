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

  # 🧠 Parse scoring summary table to get final totals
  summary_table = doc.css('table').find { |t| t.text.include?('Scoring') && t.text.include?('SO') && t.text.include?('T') }
  summary_rows = summary_table&.css('tr')&.drop(1) || []

  greenville_total = nil
  savannah_total = nil

  summary_rows.each do |row|
    cells = row.css('td').map { |td| td.text.strip }
    next unless cells.size >= 7

    team_name = cells[0]
    total = cells[-1].to_i

    if team_name.include?("Greenville")
      greenville_total = total
    elsif team_name.include?("Savannah")
      savannah_total = total
    end
  end

  # Fallback if summary table fails
  greenville_total ||= (greenville_is_away ? away_goals.size : home_goals.size)
  savannah_total ||= (greenville_is_away ? home_goals.size : away_goals.size)

  # 🧠 Determine result
  swamp_score = greenville_is_away ? greenville_total : savannah_total
  opponent_score = greenville_is_away ? savannah_total : greenville_total

  result =
    if swamp_score > opponent_score
      greenville_is_away ? "W" : "L"
    elsif swamp_score < opponent_score
      greenville_is_away ? "L" : "W"
    else
      nil # Should never happen if summary table is correct
    end

  status = "Final"
  status += " (SO)" if summary_table&.text&.include?("SO")

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

game_id = ARGV[0]
enriched = parse_game_sheet(game_id)
puts JSON.pretty_generate(enriched) if enriched
