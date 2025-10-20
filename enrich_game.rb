require 'nokogiri'
require 'open-uri'
require 'json'
require 'date'

game_id = ARGV[0]
abort("Usage: ruby enrich_game.rb GAME_ID") unless game_id

url = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id=#{game_id}&lang_id=1"
html = URI.open(url).read rescue ""
doc = Nokogiri::HTML(html)

# --- Handle unavailable or empty pages ---
if html.include?("The game is not available") || doc.text.strip.empty?
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

# --- Find SCORING table safely ---
score_table = doc.at('table.tSides:has(td:contains("SCORING"))')
if score_table.nil?
  warn "⚠️ No scoring table found for #{game_id}"
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

rows = score_table.css('tr')[2..] || []
team_rows = rows.map do |tr|
  cells = tr.css('td').map(&:text).map(&:strip)
  next if cells.empty? || cells[0].empty?
  cells
end.compact

# --- Guard against malformed tables ---
if team_rows.size < 2
  warn "⚠️ Incomplete team rows for #{game_id}"
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

away_team, home_team = team_rows[0][0], team_rows[1][0]

away_periods = team_rows[0][1..-1].map { |s| s.to_i }
home_periods = team_rows[1][1..-1].map { |s| s.to_i }

away_score = away_periods[-1]
home_score = home_periods[-1]

ot_away = team_rows[0][4].to_i rescue 0
ot_home = team_rows[1][4].to_i rescue 0
so_away = team_rows[0][5].to_i rescue 0
so_home = team_rows[1][5].to_i rescue 0

# --- Parse goal details dynamically ---
goal_table = doc.css('table').find { |t| t.text.include?("Goals") && t.text.include?("Assists") }
home_goals, away_goals = [], []

if goal_table
  goal_table.css('tr').each do |tr|
    cells = tr.css('td').map(&:text).map(&:strip)
    next if cells.empty? || cells[0] =~ /V-H/i

    team = cells[3]
    goal = cells[5]
    assists = cells[6]
    desc = assists.empty? ? goal : "#{goal} (#{assists})"

    if team && away_team && team.downcase.include?(away_team.downcase)
      away_goals << desc
    elsif team && home_team && team.downcase.include?(home_team.downcase)
      home_goals << desc
    end
  end
end

# --- Status detection ---
status =
  if html =~ /FINAL/i
    "Final"
  elsif html =~ /(In Progress|Live|2nd|3rd|OT|SO)/i
    "Live"
  else
    "Upcoming"
  end

# --- OT/SO logic ---
overtime_type =
  if (so_home + so_away) > 0
    "SO"
  elsif (ot_home + ot_away) > 0
    "OT"
  else
    nil
  end

# --- Determine result and winner ---
win = false
if status == "Final"
  if away_score > home_score
    win = true if home_team !~ /Greenville/i
  elsif home_score > away_score
    win = true if home_team =~ /Greenville/i
  end
end

# --- Add +1 for shootout win ---
if overtime_type == "SO" && win
  if home_team =~ /Greenville/i
    home_score += 1
  else
    away_score += 1
  end
end

# --- Format result correctly ---
if status == "Final"
  if overtime_type
    result = "#{win ? 'W' : 'L'}(#{overtime_type}) #{home_score}-#{away_score}"
  else
    result = "#{win ? 'W' : 'L'} #{home_score}-#{away_score}"
  end
else
  result = nil
end

# --- Output final JSON ---
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
  result: result,
  game_report_url: url
})
