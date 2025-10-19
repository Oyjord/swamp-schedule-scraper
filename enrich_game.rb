require 'open-uri'
require 'nokogiri'
require 'json'

GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def parse_game_sheet(game_id)
  url = "#{GAME_REPORT_BASE}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc  = Nokogiri::HTML(html)

  # --- 1️⃣ Parse SCORING table (top = away, bottom = home) ---
  scoring_table = doc.css('table').find { |t| t.text.include?('SCORING') }
  raise "No scoring table found for #{game_id}" unless scoring_table

  rows = scoring_table.css('tr')[2..3]
  raise "Unexpected scoring table structure" unless rows && rows.size == 2

  away_cells = rows[0].css('td').map { |td| td.text.strip }
  home_cells = rows[1].css('td').map { |td| td.text.strip }

  away_team = away_cells[0]
  home_team = home_cells[0]
  away_score = away_cells.last.to_i
  home_score = home_cells.last.to_i

  # --- Detect OT / SO ---
  overtime_type = nil
  overtime_type = "SO" if scoring_table.text.include?("SO")
  overtime_type = "OT" if scoring_table.text.include?("OT1") && !scoring_table.text.include?("SO")

  # --- 2️⃣ Parse the Goals/Assists table ---
  goal_table = doc.css('table').find do |t|
    header = t.at_css('tr')
    header && header.text.include?('Goals') && header.text.include?('Assists')
  end

  home_goals, away_goals = [], []
  team_abbrevs = {}

  if goal_table
    # Collect all team abbreviations seen in the goal table
    team_abbrevs_list = goal_table.css('td:nth-child(4)').map { |td| td.text.strip }.uniq.reject(&:empty?)
    # We'll use the first seen abbreviation for each team, e.g., "GVL" => Greenville, "UTA" => Utah, etc.
    team_abbrevs[:away] = team_abbrevs_list.find { |abbr| html.include?("#{away_team}") } || team_abbrevs_list.first
    team_abbrevs[:home] = team_abbrevs_list.find { |abbr| html.include?("#{home_team}") } || team_abbrevs_list.last
  end

  # If that fails, fall back to known ECHL team abbreviations
  team_abbrevs[:away] ||= "GVL" if away_team =~ /Greenville/i
  team_abbrevs[:home] ||= "SAV" if home_team =~ /Savannah/i
  team_abbrevs[:home] ||= "UTA" if home_team =~ /Utah/i
  team_abbrevs[:away] ||= "UTA" if away_team =~ /Utah/i

  if goal_table
    goal_table.css('tr')[1..]&.each do |row|
      tds = row.css('td')
      next unless tds.size >= 7
      team_code = tds[3].text.strip
      scorer = tds[5].text.split('(').first.strip
      assists = tds[6].text.strip
      entry = assists.empty? ? "#{scorer} (unassisted)" : "#{scorer} (#{assists})"

      if team_code == team_abbrevs[:away]
        away_goals << entry
      elsif team_code == team_abbrevs[:home]
        home_goals << entry
      end
    end
  end

  # --- 3️⃣ Handle shootout correctly ---
  if overtime_type == "SO"
    result = away_score > home_score ? "W(SO) #{away_score}-#{home_score}" : "L(SO) #{away_score}-#{home_score}"
  elsif overtime_type == "OT"
    result = away_score > home_score ? "W(OT) #{away_score}-#{home_score}" : "L(OT) #{away_score}-#{home_score}"
  else
    result = away_score > home_score ? "W #{away_score}-#{home_score}" : "L #{away_score}-#{home_score}"
  end

  {
    "game_id" => game_id.to_i,
    "status" => "Final",
    "home_team" => home_team,
    "away_team" => away_team,
    "home_score" => home_score,
    "away_score" => away_score,
    "home_goals" => home_goals,
    "away_goals" => away_goals,
    "overtime_type" => overtime_type,
    "result" => result,
    "game_report_url" => url
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
