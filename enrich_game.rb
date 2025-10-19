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

  # --- 2️⃣ Parse GOAL SUMMARY table dynamically ---
  goal_table = doc.css('table').find do |t|
    header = t.at_css('tr')
    header && header.text.match?(/Goal|Scorer/i)
  end

  home_goals, away_goals = [], []

  if goal_table
    headers = goal_table.css('tr').first.css('td,th').map { |td| td.text.strip }
    idx_team  = headers.index { |h| h.match?(/Team/i) } || 3
    idx_goal  = headers.index { |h| h.match?(/Goal|Scorer/i) } || 5
    idx_assist = headers.index { |h| h.match?(/Assist/i) } || 6

    goal_table.css('tr')[1..]&.each do |row|
      tds = row.css('td')
      next if tds.size < [idx_team, idx_goal, idx_assist].max + 1

      team_code = tds[idx_team]&.text&.strip
      scorer = tds[idx_goal]&.text&.split('(')&.first&.strip
      assists = tds[idx_assist]&.text&.strip
      entry = assists.empty? ? "#{scorer}" : "#{scorer} (#{assists})"

      case team_code
      when /GVL|GRN|Greenville/i
        away_goals << entry if away_team =~ /Greenville/i
        home_goals << entry if home_team =~ /Greenville/i
      when /SAV|Savannah/i
        away_goals << entry if away_team =~ /Savannah/i
        home_goals << entry if home_team =~ /Savannah/i
      when /UTA|Utah/i
        away_goals << entry if away_team =~ /Utah/i
        home_goals << entry if home_team =~ /Utah/i
      else
        # Fallback if abbreviation doesn’t match
        if team_code && home_team.downcase.include?(team_code.downcase)
          home_goals << entry
        elsif team_code && away_team.downcase.include?(team_code.downcase)
          away_goals << entry
        end
      end
    end
  end

  # --- 3️⃣ Detect OT / SO properly ---
  ot_goals = (away_cells[4].to_i + home_cells[4].to_i)
  so_goals = (away_cells[5].to_i + home_cells[5].to_i)
  overtime_type =
    if so_goals > 0
      "SO"
    elsif ot_goals > 0
      "OT"
    else
      nil
    end

  # --- 4️⃣ Handle shootout bonus goal correctly ---
  if overtime_type == "SO"
    if away_score == home_score
      if away_team =~ /Greenville/i
        away_score += 1
      else
        home_score += 1
      end
    end
  end

  # --- 5️⃣ Build result string from Greenville perspective ---
  greenville_is_home = home_team =~ /Greenville/i
  greenville_score = greenville_is_home ? home_score : away_score
  opponent_score   = greenville_is_home ? away_score : home_score

  if overtime_type == "SO"
    result_prefix = greenville_score > opponent_score ? "W(SO)" : "L(SO)"
  elsif overtime_type == "OT"
    result_prefix = greenville_score > opponent_score ? "W(OT)" : "L(OT)"
  else
    result_prefix = greenville_score > opponent_score ? "W" : "L"
  end

  result = "#{result_prefix} #{[greenville_score, opponent_score].max}-#{[greenville_score, opponent_score].min}"

  # --- 6️⃣ Final JSON ---
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
  warn "⚠️ Failed to parse game sheet for #{game_id}: #{e}"
  nil
end

# --- Entry point ---
if ARGV.empty?
  warn "Usage: ruby enrich_game.rb <game_id>"
  exit 1
end

game_id = ARGV[0]
data = parse_game_sheet(game_id)
puts JSON.pretty_generate(data) if data
