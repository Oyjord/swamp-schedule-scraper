require 'open-uri'
require 'nokogiri'
require 'json'

GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def parse_game_sheet(game_id)
  url = "#{GAME_REPORT_BASE}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc  = Nokogiri::HTML(html)

  # --- 1️⃣ Identify the main scoring summary table ---
  scoring_table = doc.css('table').find { |t| t.text.include?("SCORING") }
  return nil unless scoring_table

  rows = scoring_table.css('tr')
  header = rows[1]&.text&.strip
  data_rows = rows.select { |r| r.css('td').any? && r.text.strip.size > 0 }[0..1]
  return nil if data_rows.nil? || data_rows.empty?

  # Detect which row is HOME and which is VISITOR
  if header&.upcase&.include?("HOME")
    home_row = data_rows.find { |r| r.text =~ /HOME|Host/i } || data_rows[1]
    away_row = data_rows.find { |r| r.text =~ /VIS|Visitor|Away/i } || data_rows[0]
  else
    # fallback: first row = away, second = home
    away_row, home_row = data_rows
  end

  home_name = home_row.css('td')[0]&.text&.strip
  away_name = away_row.css('td')[0]&.text&.strip
  home_total = home_row.css('td').last&.text&.strip.to_i
  away_total = away_row.css('td').last&.text&.strip.to_i

  # --- 2️⃣ Determine OT / SO ---
  overtime_type = nil
  overtime_type = "SO" if doc.text.include?("SHOOTOUT")
  overtime_type ||= "OT" if scoring_table.text.include?("OT1")

  # --- 3️⃣ Parse the goals table ---
  goal_table = doc.css('table').find do |t|
    header = t.at_css('tr')
    header && header.text.include?('Goals') && header.text.include?('Assists')
  end

  home_goals, away_goals = [], []
  abbrev_map = {}

  # Try to infer the abbreviations used for each team from the table
  if goal_table
    abbrevs = goal_table.css('td:nth-child(4)').map { |td| td.text.strip }.uniq.reject(&:empty?)
    # Find likely abbreviations for home and away based on the first letter match
    abbrevs.each do |abbr|
      if away_name.downcase.start_with?(abbr[0,3].downcase) || away_name.downcase.include?(abbr[0,3].downcase)
        abbrev_map[:away] = abbr
      elsif home_name.downcase.start_with?(abbr[0,3].downcase) || home_name.downcase.include?(abbr[0,3].downcase)
        abbrev_map[:home] = abbr
      end
    end
  end

  # If we couldn’t detect, fall back to known ones
  abbrev_map[:away] ||= "GVL" if away_name =~ /Greenville/i
  abbrev_map[:home] ||= "SAV" if home_name =~ /Savannah/i

  if goal_table
    goal_rows = goal_table.css('tr')[1..] || []
    goal_rows.each do |row|
      tds = row.css('td')
      next unless tds.size >= 7

      team_abbrev = tds[3].text.strip
      scorer = tds[5].text.split('(').first.strip
      assists = tds[6].text.strip
      entry = assists.empty? ? "#{scorer} (unassisted)" : "#{scorer} (#{assists})"

      if team_abbrev == abbrev_map[:away]
        away_goals << entry
      elsif team_abbrev == abbrev_map[:home]
        home_goals << entry
      end
    end
  end

  # --- 4️⃣ Build final JSON structure ---
  # DO NOT add +1 for SO — SCORING table totals already include it
  if away_total > home_total
    result = overtime_type ? "W(#{overtime_type}) #{away_total}-#{home_total}" : "W #{away_total}-#{home_total}"
  elsif home_total > away_total
    result = overtime_type ? "L(#{overtime_type}) #{away_total}-#{home_total}" : "L #{away_total}-#{home_total}"
  else
    result = "T #{away_total}-#{home_total}"
  end

  {
    "game_id" => game_id.to_i,
    "home_team" => home_name,
    "away_team" => away_name,
    "home_score" => home_total,
    "away_score" => away_total,
    "home_goals" => home_goals,
    "away_goals" => away_goals,
    "game_report_url" => url,
    "status" => "Final",
    "result" => result,
    "overtime_type" => overtime_type
  }
rescue => e
  warn "⚠️ Failed to parse game sheet for game_id #{game_id}: #{e}"
  nil
end

if ARGV.empty?
  warn "Usage: ruby enrich_game.rb <game_id>"
  exit 1
end

game_id = ARGV[0]
data = parse_game_sheet(game_id)
puts JSON.pretty_generate(data) if data
