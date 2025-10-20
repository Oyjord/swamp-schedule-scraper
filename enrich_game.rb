require 'nokogiri'
require 'open-uri'
require 'json'
require 'date'

game_id = ARGV[0]
abort("Usage: ruby enrich_game.rb GAME_ID") unless game_id

url = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id=#{game_id}&lang_id=1"
html = URI.open(url).read rescue ""
doc = Nokogiri::HTML(html)

# --- Handle unavailable game pages ---
if html.include?("The game is not available")
  puts JSON.pretty_generate({
    game_id: game_id.to_i,
    status: "Unavailable",
    home_team: nil,
    away_team: nil,
    home_score: nil,
    away_score: nil,
    home_goals: [],
    away_goals: [],
    overtime_type: nil,
    result: nil,
    game_report_url: url
  })
  exit
end

# --- Find teams & scores from the SCORING table ---
score_table = doc.at('table.tSides:has(th:contains("SCORING")), table.tSides:has(td:contains("SCORING"))')
rows = score_table.css('tr')[2..] || []

team_rows = rows.map do |tr|
  cells = tr.css('td').map(&:text).map(&:strip)
  next if cells.empty? || cells[0].empty?
  cells
end.compact

away_team, home_team = team_rows[0][0], team_rows[1][0]

away_periods = team_rows[0][1..-1].map { |s| s.to_i }
home_periods = team_rows[1][1..-1].map { |s| s.to_i }

away_score = away_periods[-1]
home_score = home_periods[-1]

# Extract OT and SO goal counts for logic later
ot_away = team_rows[0][4].to_i rescue 0
ot_home = team_rows[1][4].to_i rescue 0
so_away = team_rows[0][5].to_i rescue 0
so_home = team_rows[1][5].to_i rescue 0

# --- Parse GOALS table dynamically ---
goal_table = doc.css('table').find do |t|
  header = t.text.strip
  header.include?("Goals") && header.include?("Assists")
end

home_goals, away_goals = [], []
if goal_table
  goal_table.css('tr').each do |tr|
    cells = tr.css('td').map(&:text).map(&:strip)
    next if cells.empty? || cells[0] =~ /V-H/i

    # Find team name and scorer/assists
    team = cells[3]
    goal = cells[5]
    assists = cells[6]
    desc = assists.empty? ? goal : "#{goal} (#{assists})"

    if team&.include?(away_team)
      away_goals << desc
    elsif team&.include?(home_team)
      home_goals << desc
    end
  end
end

# --- Determine status ---
status = if html.include?("FINAL") || html.include?("Final")
  "Final"
elsif html =~ /(Progress|Live|2nd|3rd|OT|SO)/i
  "Live"
else
  "Upcoming"
end

# --- Determine OT/SO and result logic ---
overtime_type = nil
if (so_home + so_away) > 0
  overtime_type = "SO"
elsif (ot_home + ot_away) > 0
  overtime_type = "OT"
end

win = false
if status == "Final"
  if away_score > home_score
    win = true if home_team =~ /Greenville/i ? false : true
  elsif home_score > away_score
    win = true if home_team =~ /Greenville/i
  end
end

# Add +1 for shootout win (ECHL convention)
if overtime_type == "SO"
  if win
    if home_team =~ /Greenville/i
      home_score += 1
    else
      away_score += 1
    end
  end
end

# Format result
if overtime_type
  result = "#{win ? 'W' : 'L'}(#{overtime_type}) #{home_score}-#{away_score}"
else
  result = "#{win ? 'W' : 'L'} #{home_score}-#{away_score}"
end

# --- Output JSON ---
puts JSON.pretty_generate({
  game_id: game_id.to_i,
  status: status,
  home_team: home_team,
  away_team: away_team,
  home_score: home_score,
  away_score: away_score,
  home_goals: home_goals,
  away_goals: away_goals,
  overtime_type: overtime_type,
  result: status == "Final" ? result : nil,
  game_report_url: url
})
