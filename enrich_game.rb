require 'open-uri'
require 'nokogiri'
require 'json'

GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def parse_game_sheet(game_id)
  url = "#{GAME_REPORT_BASE}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc  = Nokogiri::HTML(html)

  # --- 1️⃣ Parse SCORING table (away row always comes first) ---
  scoring_table = doc.css('table').find { |t| t.text.include?('SCORING') }
  raise "No scoring table found for #{game_id}" unless scoring_table

  rows = scoring_table.css('tr')[2..3] # row[2] = away, row[3] = home
  raise "Unexpected scoring table structure" unless rows && rows.size == 2

  away_cells = rows[0].css('td').map { |td| td.text.strip }
  home_cells = rows[1].css('td').map { |td| td.text.strip }

  away_team = away_cells[0]
  home_team = home_cells[0]

  away_score = away_cells.last.to_i
  home_score = home_cells.last.to_i

  # Detect if the game had OT or SO
  overtime_type = nil
  overtime_type = "SO" if scoring_table.text.include?("SO")
  overtime_type = "OT" if scoring_table.text.include?("OT1") && !scoring_table.text.include?("SO")

  # --- 2️⃣ Parse the detailed goal table ---
  goal_table = doc.css('table').find do |t|
    header = t.at_css('tr')
    header && header.text.include?('Goals') && header.text.include?('Assists')
  end

  home_goals, away_goals = [], []

  if goal_table
    goal_rows = goal_table.css('tr')[1..] || []
    goal_rows.each do |row|
      tds = row.css('td')
      next unless tds.size >= 7
      team = tds[3].text.strip
      scorer = tds[5].text.split('(').first.strip
      assists = tds[6].text.strip
      entry = assists.empty? ? "#{scorer} (unassisted)" : "#{scorer} (#{assists})"

      if team == away_team[0,3].upcase || team.include?(away_team[0,3].upcase)
        away_goals << entry
      elsif team == home_team[0,3].upcase || team.include?(home_team[0,3].upcase)
        home_goals << entry
      end
    end
  end

  # --- 3️⃣ Handle shootout correctly (+1 for the winner only) ---
  if overtime_type == "SO"
    if away_score > home_score
      result = "W(SO) #{away_score}-#{home_score}"
    else
      result = "L(SO) #{away_score}-#{home_score}"
    end
  elsif overtime_type == "OT"
    if away_score > home_score
      result = "W(OT) #{away_score}-#{home_score}"
    else
      result = "L(OT) #{away_score}-#{home_score}"
    end
  else
    if away_score > home_score
      result = "W #{away_score}-#{home_score}"
    else
      result = "L #{away_score}-#{home_score}"
    end
  end

  # --- 4️⃣ Return normalized JSON ---
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
